export interface TraceEvent {
  pid: number;
  tid: number;
  ts: number;
  dur?: number;
  ph: string;
  name: string;
  cat: string;
  args?: Record<string, any>;
  sf?: number;
  stack?: any[];
  id?: string;
  scope?: string;
}

export interface ProcessInfo {
  pid: number;
  name: string;
  threads: ThreadInfo[];
}

export interface ThreadInfo {
  tid: number;
  name: string;
  events: TraceEvent[];
}

export interface TraceData {
  processes: ProcessInfo[];
  metadata: {
    totalDuration: number;
    startTime: number;
    endTime: number;
    eventCount: number;
  };
}

export interface FilterCriteria {
  processIds?: number[];
  threadIds?: number[];
  categories?: string[];
  eventTypes?: string[];
  minDuration?: number;
  maxDuration?: number;
  timeRange?: [number, number];
  searchTerm?: string;
}

export interface Statistics {
  totalEvents: number;
  averageDuration: number;
  longestEvent: TraceEvent | null;
  shortestEvent: TraceEvent | null;
  categoryDistribution: Record<string, number>;
  phaseDistribution: Record<string, number>;
  processDistribution: Record<number, number>;
}