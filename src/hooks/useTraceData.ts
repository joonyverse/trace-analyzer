import { useState, useCallback, useMemo } from 'react';
import { TraceData, TraceEvent, FilterCriteria, Statistics } from '../types/TraceEvent';
import { TraceParser } from '../utils/traceParser';

export const useTraceData = () => {
  const [traceData, setTraceData] = useState<TraceData | null>(null);
  const [filters, setFilters] = useState<FilterCriteria>({});
  const [selectedEvent, setSelectedEvent] = useState<TraceEvent | null>(null);
  const [viewportRange, setViewportRange] = useState<[number, number]>([0, 1]);
  const [isLoading, setIsLoading] = useState(false);

  const loadTraceFile = useCallback(async (file: File) => {
    setIsLoading(true);
    try {
      const text = await file.text();
      const jsonData = JSON.parse(text);
      const parsedData = TraceParser.parseTraceData(jsonData);
      setTraceData(parsedData);
      setViewportRange([parsedData.metadata.startTime, parsedData.metadata.endTime]);
    } catch (error) {
      console.error('Failed to parse trace file:', error);
    } finally {
      setIsLoading(false);
    }
  }, []);

  const filteredEvents = useMemo(() => {
    if (!traceData) return [];
    
    const allEvents = traceData.processes.flatMap(p => 
      p.threads.flatMap(t => t.events)
    );
    
    return TraceParser.filterEvents(allEvents, filters);
  }, [traceData, filters]);

  const statistics = useMemo(() => {
    return TraceParser.calculateStatistics(filteredEvents);
  }, [filteredEvents]);

  const visibleEvents = useMemo(() => {
    return filteredEvents.filter(event => 
      event.ts >= viewportRange[0] && event.ts <= viewportRange[1]
    );
  }, [filteredEvents, viewportRange]);

  return {
    traceData,
    filteredEvents,
    visibleEvents,
    statistics,
    filters,
    selectedEvent,
    viewportRange,
    isLoading,
    loadTraceFile,
    setFilters,
    setSelectedEvent,
    setViewportRange
  };
};