import type { TranscriptSegment } from "./asr-client.js"
import { SpeakerTracker, type SpeakerProfile } from "./speaker-tracker.js"
import { classifyTextInput } from "./text-metadata.js"
import { writeFileSync, existsSync, mkdirSync } from "fs"
import { join } from "path"

// ── Types ──────────────────────────────────────────────────────────

interface RecentInput {
  speaker: string // speaker label or "typed"
  source: "voice" | "text"
  text: string
  emotion: string
  intent: string
  timestamp: number
}

interface ConversationDynamics {
  agreementLevel: string // "aligned", "mixed", "divergent"
  urgencyLevel: string // "low", "moderate", "high"
  planningCues: string // natural language summary
  recommendation: PlanningRecommendation
}

interface PlanningRecommendation {
  action: "ask" | "proceed" | "present-options"
  reason: string
  suggestedFocus: string // what to ask about or act on
}

// ── Session Context Store ──────────────────────────────────────────

/**
 * Multi-speaker context store that tracks voice and text inputs,
 * generates .claude-voice/context.md for Claude to read.
 */
export class SessionContextStore {
  private speakerTracker: SpeakerTracker
  private recentInputs: RecentInput[] = []
  private readonly maxRecent = 10
  private outputPath: string
  private sessionStart = Date.now()

  constructor(speakerLabels?: string[], outputDir?: string) {
    this.speakerTracker = new SpeakerTracker(speakerLabels)
    const dir = outputDir ?? join(process.cwd(), ".claude-voice")
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true })
    this.outputPath = join(dir, "context.md")
  }

  get filePath(): string {
    return this.outputPath
  }

  // ── Voice ingestion ────────────────────────────────────────────

  /** Ingest a voice transcript segment. Returns the identified speaker label. */
  ingestVoice(seg: TranscriptSegment): { speakerLabel: string } {
    if (!seg.is_final) return { speakerLabel: "" }

    // Identify speaker
    let speaker: SpeakerProfile | null = null
    if (seg.speaker_embedding && seg.speaker_embedding.length > 0) {
      speaker = this.speakerTracker.identify(seg.speaker_embedding)
    } else {
      speaker = this.speakerTracker.identifyByChange(seg.speaker_change ?? false)
    }

    const speakerLabel = speaker?.label ?? "Unknown"
    const speakerId = speaker?.id ?? ""

    // Ingest metadata for this speaker
    if (speakerId) {
      this.speakerTracker.ingestForSpeaker(speakerId, seg)
    }

    // Add to recent inputs
    if (seg.text.trim()) {
      this.addRecent({
        speaker: speakerLabel,
        source: "voice",
        text: seg.text.trim(),
        emotion: seg.metadata?.emotion ?? "",
        intent: seg.metadata?.intent ?? "",
        timestamp: Date.now(),
      })
    }

    this.flush()
    return { speakerLabel }
  }

  // ── Text ingestion ─────────────────────────────────────────────

  /** Ingest typed text input with auto-classified metadata. */
  ingestText(text: string): void {
    if (!text.trim()) return

    const meta = classifyTextInput(text)

    // Always attribute to a speaker — create default if none exist yet
    const primarySpeaker = this.speakerTracker.ensureDefaultSpeaker()
    const speakerLabel = primarySpeaker.label

    this.speakerTracker.ingestTextForSpeaker(
      primarySpeaker.id,
      meta.dominantEmotion,
      meta.dominantIntent,
    )

    this.addRecent({
      speaker: speakerLabel,
      source: "text",
      text: text.trim().slice(0, 200),
      emotion: meta.dominantEmotion,
      intent: meta.dominantIntent,
      timestamp: Date.now(),
    })

    this.flush()
  }

  // ── Summary for terminal title ─────────────────────────────────

  get shortSummary(): string {
    const last = this.speakerTracker.lastSpeaker
    if (!last) return ""

    const parts: string[] = []
    parts.push(`[${last.label}]`)
    if (last.meta.currentEmotion) parts.push(last.meta.currentEmotion)
    if (last.meta.currentIntent) parts.push(last.meta.currentIntent)
    if (last.meta.avgWpm > 0) parts.push(`${last.meta.avgWpm}wpm`)
    return parts.join(" · ")
  }

  // ── Markdown generation ────────────────────────────────────────

  toMarkdown(): string {
    const speakers = this.speakerTracker.activeSpeakers
    if (this.recentInputs.length === 0 && speakers.length === 0) return ""

    const lines: string[] = [
      "# Voice Session Context",
      "",
      "> Auto-updated by claude-voice after each input (voice or text).",
      "",
    ]

    const isSingleSpeaker = speakers.length <= 1

    // Current state
    lines.push("## Current State")
    const lastInput = this.recentInputs[this.recentInputs.length - 1]
    if (!isSingleSpeaker) {
      const labels = speakers.map((s) => s.label).join(", ")
      lines.push(`**Active speakers:** ${speakers.length} (${labels})`)
    }

    // Input modality summary
    const voiceCount = this.recentInputs.filter((r) => r.source === "voice").length
    const textCount = this.recentInputs.filter((r) => r.source === "text").length
    if (voiceCount > 0 && textCount > 0) {
      lines.push(`**Input mix:** ${voiceCount} voice, ${textCount} text`)
    } else if (voiceCount > 0) {
      lines.push(`**Input mode:** voice`)
    } else if (textCount > 0) {
      lines.push(`**Input mode:** text`)
    }

    if (lastInput) {
      lines.push(
        `**Last input:** ${lastInput.source}` +
          (!isSingleSpeaker ? ` from ${lastInput.speaker}` : "") +
          (lastInput.emotion ? ` — emotion: ${lastInput.emotion}` : "") +
          (lastInput.intent ? `, intent: ${lastInput.intent}` : ""),
      )
    }

    // Session dynamics summary
    const dynamics = this.recentInputs.length >= 2 ? this.analyzeDynamics() : null
    if (dynamics) {
      lines.push(`**Session mood:** urgency ${dynamics.urgencyLevel}`)
    }
    lines.push("")

    // User profile (single speaker) or Speaker profiles (multi)
    if (speakers.length > 0) {
      lines.push(isSingleSpeaker ? "## User Profile" : "## Speaker Profiles")
      lines.push("")
      for (const sp of speakers) {
        const m = sp.meta
        if (!isSingleSpeaker) lines.push(`### ${sp.label}`)

        // Emotion trend — more useful than just current
        if (m.recentEmotions.length > 0) {
          const recent = m.recentEmotions.slice(-5).join(", ")
          const trend = this.emotionTrend(m.recentEmotions)
          lines.push(`- **Emotion:** ${m.currentEmotion}${trend ? ` (${trend})` : ""} — recent: ${recent}`)
        }
        if (Object.keys(m.intentCounts).length > 0) {
          const total = Object.values(m.intentCounts).reduce((a, b) => a + b, 0)
          const sorted = Object.entries(m.intentCounts)
            .sort((a, b) => b[1] - a[1])
            .slice(0, 3)
          const dist = sorted.map(([k, v]) => `${k} ${Math.round((v / total) * 100)}%`).join(", ")
          lines.push(`- **Intent pattern:** ${dist}`)
        }
        if (m.avgWpm > 0) {
          const pace = m.avgWpm > 160 ? "fast" : m.avgWpm > 130 ? "normal" : "deliberate"
          lines.push(`- **Speech rate:** ${m.avgWpm} wpm (${pace})`)
        }
        if (m.totalFillers > 0) {
          const fillerRate = m.segmentCount > 0 ? (m.totalFillers / m.segmentCount).toFixed(1) : "0"
          lines.push(`- **Filler words:** ${m.totalFillers} (${fillerRate}/utterance)`)
        }
        lines.push(`- **Total inputs:** ${m.segmentCount}`)
        lines.push("")
      }
    }

    // Conversation dynamics + Planning recommendations
    if (dynamics) {
      if (!isSingleSpeaker || this.recentInputs.length >= 3) {
        lines.push("## Conversation Flow")
        if (!isSingleSpeaker) {
          lines.push(`- **Agreement:** ${dynamics.agreementLevel}`)
        }
        lines.push(`- **Urgency:** ${dynamics.urgencyLevel}`)
        lines.push(`- **Pattern:** ${dynamics.planningCues}`)
        lines.push("")
      }

      const rec = dynamics.recommendation
      lines.push("## Planning Recommendations")
      const actionLabel = rec.action === "ask"
        ? "ASK a clarifying question"
        : rec.action === "present-options"
          ? "PRESENT 2-3 options"
          : "PROCEED with execution"
      lines.push(`**Action:** ${actionLabel}`)
      lines.push(`**Why:** ${rec.reason}`)
      lines.push(`**Focus:** ${rec.suggestedFocus}`)
      lines.push("")
    } else if (this.recentInputs.length === 1) {
      // First input — always recommend asking to understand scope
      const lastInput = this.recentInputs[0]
      const isCommand = lastInput.intent?.includes("COMMAND")
      lines.push("## Planning Recommendations")
      if (isCommand) {
        lines.push(`**Action:** PROCEED with execution`)
        lines.push(`**Why:** User gave a clear, direct instruction`)
        lines.push(`**Focus:** ${lastInput.text}`)
      } else {
        lines.push(`**Action:** ASK a clarifying question`)
        lines.push(`**Why:** First input of the session — confirm scope and constraints before planning`)
        lines.push(`**Focus:** Ask about scope, priorities, or constraints for: "${lastInput.text.slice(0, 60)}"`)
      }
      lines.push("")
    }

    // Recent inputs
    if (this.recentInputs.length > 0) {
      lines.push("## Recent Inputs")
      const show = this.recentInputs.slice(-7)
      for (let i = 0; i < show.length; i++) {
        const r = show[i]
        const truncText = r.text.length > 80 ? r.text.slice(0, 80) + "..." : r.text
        const meta = [r.emotion, r.intent].filter(Boolean).join(", ")
        lines.push(`${i + 1}. [${r.speaker}/${r.source}] "${truncText}"${meta ? ` — ${meta}` : ""}`)
      }
      lines.push("")
    }

    return lines.join("\n")
  }

  /** Write context.md to disk. */
  flush(): void {
    const md = this.toMarkdown()
    if (md) {
      try {
        writeFileSync(this.outputPath, md, "utf-8")
      } catch {}
    }
  }

  // ── Private helpers ────────────────────────────────────────────

  private emotionTrend(emotions: string[]): string {
    if (emotions.length < 3) return ""
    const last3 = emotions.slice(-3)
    if (last3.every((e) => e === last3[0])) return `steady`
    const first = emotions.slice(0, Math.floor(emotions.length / 2))
    const second = emotions.slice(Math.floor(emotions.length / 2))
    const mode = (arr: string[]) => {
      const counts: Record<string, number> = {}
      for (const v of arr) counts[v] = (counts[v] ?? 0) + 1
      return Object.entries(counts).sort((a, b) => b[1] - a[1])[0]?.[0] ?? ""
    }
    const f = mode(first)
    const s = mode(second)
    if (f && s && f !== s) return `shifting ${f} → ${s}`
    return ""
  }

  private addRecent(input: RecentInput): void {
    this.recentInputs.push(input)
    if (this.recentInputs.length > this.maxRecent) {
      this.recentInputs.shift()
    }
  }

  private analyzeDynamics(): ConversationDynamics {
    const recent = this.recentInputs.slice(-5)

    // Agreement — check if speakers share similar emotions
    const emotions = recent.map((r) => r.emotion).filter(Boolean)
    const uniqueEmotions = new Set(emotions)
    let agreementLevel = "neutral"
    if (uniqueEmotions.size <= 1 && emotions.length >= 2) {
      const emo = emotions[0] ?? "NEUTRAL"
      agreementLevel = emo === "HAPPY" ? "aligned and positive" : emo === "ANGRY" ? "shared frustration" : "aligned"
    } else if (uniqueEmotions.size >= 3) {
      agreementLevel = "mixed signals"
    } else {
      agreementLevel = "mostly aligned"
    }

    // Urgency — high WPM or negative emotions
    const speakers = this.speakerTracker.activeSpeakers
    const wpms = speakers.map((s) => s.meta.avgWpm).filter((w) => w > 0)
    const avgWpm = wpms.length > 0 ? wpms.reduce((a, b) => a + b, 0) / wpms.length : 0
    const hasNegative = emotions.some((e) => ["ANGRY", "SAD"].includes(e))
    let urgencyLevel = "low"
    if (avgWpm > 160 || hasNegative) urgencyLevel = "high"
    else if (avgWpm > 140) urgencyLevel = "moderate"

    // Planning cues — intent distribution
    const intents = recent.map((r) => r.intent).filter(Boolean)
    const queryCount = intents.filter((i) => i.includes("QUERY")).length
    const commandCount = intents.filter((i) => i.includes("COMMAND")).length
    const informCount = intents.filter((i) => i.includes("INFORM")).length
    const isSingle = this.speakerTracker.activeSpeakers.length <= 1
    const who = isSingle ? "user is" : "speakers are"
    let planningCues = "general discussion"
    if (intents.length >= 3) {
      if (queryCount / intents.length > 0.5) {
        planningCues = `${who} exploring options and asking questions`
      } else if (commandCount / intents.length > 0.5) {
        planningCues = `${who} ready to execute — action-oriented`
      } else if (informCount / intents.length > 0.5) {
        planningCues = `${who} thinking aloud — sharing context without a clear ask yet`
      } else {
        planningCues = "mix of exploration and direction"
      }
    }

    // ── Planning recommendation ────────────────────────────────
    const recommendation = this.deriveRecommendation({
      recent,
      emotions,
      intents,
      queryCount,
      commandCount,
      informCount,
      agreementLevel,
      urgencyLevel,
      hasNegative,
      speakerCount: speakers.length,
    })

    return { agreementLevel, urgencyLevel, planningCues, recommendation }
  }

  private deriveRecommendation(ctx: {
    recent: RecentInput[]
    emotions: string[]
    intents: string[]
    queryCount: number
    commandCount: number
    informCount: number
    agreementLevel: string
    urgencyLevel: string
    hasNegative: boolean
    speakerCount: number
  }): PlanningRecommendation {
    const { recent, intents, queryCount, commandCount, informCount,
            urgencyLevel, hasNegative, speakerCount } = ctx

    const isSingleSpeaker = speakerCount <= 1
    const lastTwo = recent.slice(-2)
    const lastInput = recent[recent.length - 1]

    // ── Shared signals ─────────────────────────────────────────

    // Confusion / frustration signals
    const hasConfusion = ctx.emotions.some((e) => ["SAD", "ANGRY"].includes(e))
    const highFillers = this.speakerTracker.activeSpeakers.some(
      (s) => s.meta.totalFillers > 3 && s.meta.segmentCount > 2,
    )

    // Intent shift — user changed what they're doing (exploring → commanding, etc.)
    const intentShift = lastTwo.length === 2
      && lastTwo[0].intent !== lastTwo[1].intent
      && lastTwo[0].intent && lastTwo[1].intent

    // ── Single-speaker triggers ────────────────────────────────

    if (isSingleSpeaker) {
      // High urgency + commands → just do it
      if (urgencyLevel === "high" && commandCount >= 2) {
        return {
          action: "proceed",
          reason: "User is giving direct commands with urgency",
          suggestedFocus: lastInput?.text ?? "",
        }
      }

      // Frustration or high filler rate → pause and clarify
      if (hasConfusion || highFillers) {
        return {
          action: "ask",
          reason: hasConfusion
            ? "User seems frustrated or uncertain — clarify before proceeding"
            : "High filler word rate suggests the user is thinking through the problem",
          suggestedFocus: "Ask a specific clarifying question about the most recent point",
        }
      }

      // User shifted from exploring to commanding → ready to go
      if (intentShift && lastInput?.intent?.includes("COMMAND")) {
        return {
          action: "proceed",
          reason: "User shifted from exploring to giving a direct instruction",
          suggestedFocus: lastInput.text,
        }
      }

      // User shifted from commanding to asking → wants to rethink
      if (intentShift && lastInput?.intent?.includes("QUERY")) {
        return {
          action: "present-options",
          reason: "User was directing but is now asking questions — reconsidering approach",
          suggestedFocus: "Present alternatives for what they're questioning",
        }
      }

      // Query-heavy — user is exploring, help them narrow down
      if (intents.length >= 2 && queryCount / intents.length > 0.5) {
        return {
          action: "present-options",
          reason: "User is asking questions — still exploring the problem space",
          suggestedFocus: "Present 2-3 concrete options to help narrow down the approach",
        }
      }

      // Inform-heavy — user is thinking aloud, help them land on a decision
      if (intents.length >= 3 && informCount / intents.length > 0.6) {
        return {
          action: "ask",
          reason: "User is sharing context and thinking aloud but hasn't landed on a clear goal",
          suggestedFocus: "Ask what outcome they're looking for from what they've described",
        }
      }

      // Command-heavy → proceed
      if (commandCount >= 2) {
        return {
          action: "proceed",
          reason: "User is giving clear, direct instructions",
          suggestedFocus: lastInput?.text ?? "",
        }
      }

      // Mixed voice + text — user is using voice for thinking, text for precision
      const voiceRecent = recent.filter((r) => r.source === "voice").length
      const textRecent = recent.filter((r) => r.source === "text").length
      if (voiceRecent > 0 && textRecent > 0 && lastInput?.source === "voice") {
        return {
          action: "ask",
          reason: "User is mixing voice (thinking) and text (precision) — voice input may need refinement",
          suggestedFocus: "Confirm the voice input captures what they meant, then proceed",
        }
      }

      // Not enough signal — ask a scoping question
      if (recent.length < 3) {
        return {
          action: "ask",
          reason: "Early in the conversation — not enough context yet",
          suggestedFocus: "Ask a scoping question to understand the goal and constraints",
        }
      }

      // Steady flow → proceed
      return {
        action: "proceed",
        reason: "Conversation is flowing with clear intent",
        suggestedFocus: lastInput?.text ?? "",
      }
    }

    // ── Multi-speaker triggers ─────────────────────────────────

    // Topic shift between different speakers
    const topicShift = lastTwo.length === 2
      && lastTwo[0].speaker !== lastTwo[1].speaker
      && lastTwo[0].intent !== lastTwo[1].intent

    // Multi-speaker disagreement
    const speakerIntents = new Map<string, string>()
    for (const r of recent) {
      if (r.intent) speakerIntents.set(r.speaker, r.intent)
    }
    const uniqueSpeakerIntents = new Set(speakerIntents.values())
    const speakerDisagreement = uniqueSpeakerIntents.size >= 2 && speakerIntents.size >= 2

    // High urgency + command-heavy → proceed
    if (urgencyLevel === "high" && commandCount >= 2) {
      return {
        action: "proceed",
        reason: "Urgency is high and speakers are giving direct commands",
        suggestedFocus: lastInput?.text ?? "",
      }
    }

    // Speakers disagreeing → surface it
    if (speakerDisagreement && topicShift) {
      const speakers = [...speakerIntents.entries()]
      return {
        action: "ask",
        reason: `Speakers have different intents — ${speakers.map(([s, i]) => `${s}: ${i}`).join(", ")}`,
        suggestedFocus: "Clarify which direction to take before planning further",
      }
    }

    // Confusion / frustration → clarify
    if (hasConfusion || highFillers) {
      const who = recent.filter((r) => ["SAD", "ANGRY"].includes(r.emotion)).map((r) => r.speaker)
      const uniqueWho = [...new Set(who)]
      return {
        action: "ask",
        reason: `Uncertainty detected${uniqueWho.length ? ` from ${uniqueWho.join(", ")}` : ""}`,
        suggestedFocus: "Check understanding before proceeding",
      }
    }

    // Query-heavy → exploring
    if (intents.length >= 3 && queryCount / intents.length > 0.5) {
      return {
        action: "present-options",
        reason: "Speakers are asking questions — still exploring",
        suggestedFocus: "Present 2-3 concrete options to help narrow down",
      }
    }

    // Topic shift → verify
    if (topicShift) {
      const newInput = lastTwo[1]
      return {
        action: "ask",
        reason: `${newInput.speaker} shifted direction from ${lastTwo[0].speaker}'s thread`,
        suggestedFocus: `Confirm whether to follow ${newInput.speaker}'s direction`,
      }
    }

    // Command-heavy → proceed
    if (commandCount >= 2) {
      return {
        action: "proceed",
        reason: "Speakers are aligned and giving clear direction",
        suggestedFocus: lastInput?.text ?? "",
      }
    }

    // Inform-heavy → ask for goal
    if (intents.length >= 3 && informCount / intents.length > 0.6) {
      return {
        action: "ask",
        reason: "Speakers are sharing context but haven't stated a clear goal",
        suggestedFocus: "Ask what they'd like to do with the information shared",
      }
    }

    // Default
    if (recent.length >= 3) {
      return {
        action: "proceed",
        reason: "Conversation is flowing naturally",
        suggestedFocus: lastInput?.text ?? "",
      }
    }

    return {
      action: "ask",
      reason: "Not enough signal yet",
      suggestedFocus: "Ask a scoping question to understand the desired outcome",
    }
  }
}
