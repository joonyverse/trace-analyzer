import { TraceEvent, TraceData, ProcessInfo, ThreadInfo, Statistics } from '../types/TraceEvent';

export class TraceParser {
  static parseTraceData(jsonData: any[]): TraceData {
    const processMap = new Map<number, ProcessInfo>();
    let startTime = Infinity;
    let endTime = -Infinity;

    // Group events by process and thread
    jsonData.forEach(event => {
      if (!event.pid || !event.tid) return;

      startTime = Math.min(startTime, event.ts);
      endTime = Math.max(endTime, event.ts + (event.dur || 0));

      let process = processMap.get(event.pid);
      if (!process) {
        process = {
          pid: event.pid,
          name: event.args?.name || `Process ${event.pid}`,
          threads: []
        };
        processMap.set(event.pid, process);
      }

      let thread = process.threads.find(t => t.tid === event.tid);
      if (!thread) {
        thread = {
          tid: event.tid,
          name: event.args?.name || `Thread ${event.tid}`,
          events: []
        };
        process.threads.push(thread);
      }

      thread.events.push(event);
    });

    // Sort events by timestamp
    processMap.forEach(process => {
      process.threads.forEach(thread => {
        thread.events.sort((a, b) => a.ts - b.ts);
      });
    });

    return {
      processes: Array.from(processMap.values()),
      metadata: {
        totalDuration: endTime - startTime,
        startTime,
        endTime,
        eventCount: jsonData.length
      }
    };
  }

  static calculateStatistics(events: TraceEvent[]): Statistics {
    if (events.length === 0) {
      return {
        totalEvents: 0,
        averageDuration: 0,
        longestEvent: null,
        shortestEvent: null,
        categoryDistribution: {},
        phaseDistribution: {},
        processDistribution: {}
      };
    }

    const durations = events.filter(e => e.dur !== undefined).map(e => e.dur!);
    const averageDuration = durations.length > 0 ? durations.reduce((a, b) => a + b, 0) / durations.length : 0;
    
    const longestEvent = events.reduce((prev, current) => 
      (prev.dur || 0) > (current.dur || 0) ? prev : current
    );
    
    const shortestEvent = events.reduce((prev, current) => 
      (prev.dur || Infinity) < (current.dur || Infinity) ? prev : current
    );

    const categoryDistribution: Record<string, number> = {};
    const phaseDistribution: Record<string, number> = {};
    const processDistribution: Record<number, number> = {};

    events.forEach(event => {
      categoryDistribution[event.cat] = (categoryDistribution[event.cat] || 0) + 1;
      phaseDistribution[event.ph] = (phaseDistribution[event.ph] || 0) + 1;
      processDistribution[event.pid] = (processDistribution[event.pid] || 0) + 1;
    });

    return {
      totalEvents: events.length,
      averageDuration,
      longestEvent,
      shortestEvent,
      categoryDistribution,
      phaseDistribution,
      processDistribution
    };
  }

  static filterEvents(events: TraceEvent[], criteria: any): TraceEvent[] {
    return events.filter(event => {
      if (criteria.processIds?.length && !criteria.processIds.includes(event.pid)) return false;
      if (criteria.threadIds?.length && !criteria.threadIds.includes(event.tid)) return false;
      if (criteria.categories?.length && !criteria.categories.includes(event.cat)) return false;
      if (criteria.eventTypes?.length && !criteria.eventTypes.includes(event.ph)) return false;
      if (criteria.minDuration !== undefined && (event.dur || 0) < criteria.minDuration) return false;
      if (criteria.maxDuration !== undefined && (event.dur || 0) > criteria.maxDuration) return false;
      if (criteria.timeRange && (event.ts < criteria.timeRange[0] || event.ts > criteria.timeRange[1])) return false;
      if (criteria.searchTerm && !event.name.toLowerCase().includes(criteria.searchTerm.toLowerCase())) return false;
      
      return true;
    });
  }
}