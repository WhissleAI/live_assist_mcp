import type { TranscriptSegment } from "./asr-client.js"

export interface PerSpeakerMetadata {
  emotionCounts: Record<string, number>
  intentCounts: Record<string, number>
  currentEmotion: string
  currentIntent: string
  avgWpm: number
  recentEmotions: string[]
  segmentCount: number
  wpmSamples: number[]
  totalFillers: number
  totalPauses: number
}

export interface SpeakerProfile {
  id: string
  label: string
  centroid: number[]
  sampleCount: number
  meta: PerSpeakerMetadata
}

function freshMeta(): PerSpeakerMetadata {
  return {
    emotionCounts: {},
    intentCounts: {},
    currentEmotion: "",
    currentIntent: "",
    avgWpm: 0,
    recentEmotions: [],
    segmentCount: 0,
    wpmSamples: [],
    totalFillers: 0,
    totalPauses: 0,
  }
}

function cosineSimilarity(a: number[], b: number[]): number {
  if (a.length !== b.length || a.length === 0) return 0
  let dot = 0
  let normA = 0
  let normB = 0
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i]
    normA += a[i] * a[i]
    normB += b[i] * b[i]
  }
  const denom = Math.sqrt(normA) * Math.sqrt(normB)
  return denom === 0 ? 0 : dot / denom
}

export class SpeakerTracker {
  private speakers: SpeakerProfile[] = []
  private readonly threshold = 0.75
  private readonly maxSpeakers: number
  private readonly labels: string[]
  private lastSpeakerId: string = ""

  constructor(labels?: string[], maxSpeakers = 4) {
    this.labels = labels ?? []
    this.maxSpeakers = maxSpeakers
  }

  /** Identify speaker from embedding. Creates new profile if unrecognized. */
  identify(embedding: number[]): SpeakerProfile {
    let bestMatch: SpeakerProfile | null = null
    let bestSim = -1

    for (const sp of this.speakers) {
      const sim = cosineSimilarity(embedding, sp.centroid)
      if (sim > bestSim) {
        bestSim = sim
        bestMatch = sp
      }
    }

    if (bestMatch && bestSim >= this.threshold) {
      this.updateCentroid(bestMatch, embedding)
      this.lastSpeakerId = bestMatch.id
      return bestMatch
    }

    if (this.speakers.length >= this.maxSpeakers) {
      // At capacity — assign to closest match even if below threshold
      if (bestMatch) {
        this.updateCentroid(bestMatch, embedding)
        this.lastSpeakerId = bestMatch.id
        return bestMatch
      }
    }

    // Create new speaker
    const idx = this.speakers.length
    const id = `speaker-${String.fromCharCode(97 + idx)}` // speaker-a, speaker-b, ...
    const label = this.labels[idx] ?? `Speaker ${String.fromCharCode(65 + idx)}`
    const profile: SpeakerProfile = {
      id,
      label,
      centroid: [...embedding],
      sampleCount: 1,
      meta: freshMeta(),
    }
    this.speakers.push(profile)
    this.lastSpeakerId = id
    return profile
  }

  /** When no embedding available, use speaker_change flag to toggle. */
  identifyByChange(speakerChange: boolean): SpeakerProfile | null {
    if (this.speakers.length === 0) return null

    if (speakerChange && this.speakers.length >= 2) {
      // Toggle to the other speaker
      const other = this.speakers.find((s) => s.id !== this.lastSpeakerId)
      if (other) {
        this.lastSpeakerId = other.id
        return other
      }
    }

    return this.speakers.find((s) => s.id === this.lastSpeakerId) ?? this.speakers[0]
  }

  /** Ingest metadata from a transcript segment for a given speaker. */
  ingestForSpeaker(speakerId: string, seg: TranscriptSegment): void {
    const sp = this.speakers.find((s) => s.id === speakerId)
    if (!sp) return
    const m = sp.meta

    m.segmentCount++

    const emotion = seg.metadata?.emotion
    if (emotion) {
      m.emotionCounts[emotion] = (m.emotionCounts[emotion] ?? 0) + 1
      m.currentEmotion = emotion
      m.recentEmotions.push(emotion)
      if (m.recentEmotions.length > 10) m.recentEmotions.shift()
    }

    const intent = seg.metadata?.intent
    if (intent) {
      m.intentCounts[intent] = (m.intentCounts[intent] ?? 0) + 1
      m.currentIntent = intent
    }

    if (seg.speech_rate) {
      if (seg.speech_rate.words_per_minute > 0) {
        m.wpmSamples.push(seg.speech_rate.words_per_minute)
        m.avgWpm = Math.round(m.wpmSamples.reduce((a, b) => a + b, 0) / m.wpmSamples.length)
      }
      m.totalFillers += seg.speech_rate.filler_count
      m.totalPauses += seg.speech_rate.pause_count
    }
  }

  /** Update per-speaker metadata from text input. */
  ingestTextForSpeaker(
    speakerId: string,
    emotion: string,
    intent: string,
  ): void {
    const sp = this.speakers.find((s) => s.id === speakerId)
    if (!sp) return
    const m = sp.meta
    m.segmentCount++
    if (emotion) {
      m.emotionCounts[emotion] = (m.emotionCounts[emotion] ?? 0) + 1
      m.currentEmotion = emotion
      m.recentEmotions.push(emotion)
      if (m.recentEmotions.length > 10) m.recentEmotions.shift()
    }
    if (intent) {
      m.intentCounts[intent] = (m.intentCounts[intent] ?? 0) + 1
      m.currentIntent = intent
    }
  }

  /** Ensure a default speaker exists (for text-only sessions). */
  ensureDefaultSpeaker(): SpeakerProfile {
    if (this.speakers.length > 0) return this.speakers[0]
    const label = this.labels[0] ?? "user"
    const profile: SpeakerProfile = {
      id: "speaker-a",
      label,
      centroid: [],
      sampleCount: 0,
      meta: freshMeta(),
    }
    this.speakers.push(profile)
    this.lastSpeakerId = profile.id
    return profile
  }

  get activeSpeakers(): ReadonlyArray<Readonly<SpeakerProfile>> {
    return this.speakers
  }

  get lastSpeaker(): SpeakerProfile | null {
    return this.speakers.find((s) => s.id === this.lastSpeakerId) ?? null
  }

  private updateCentroid(sp: SpeakerProfile, embedding: number[]): void {
    const n = sp.sampleCount
    for (let i = 0; i < sp.centroid.length; i++) {
      sp.centroid[i] = (sp.centroid[i] * n + embedding[i]) / (n + 1)
    }
    sp.sampleCount++
  }
}
