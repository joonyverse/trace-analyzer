import React, { useState, useMemo } from 'react';
import { List, Search, Filter, Clock, Zap } from 'lucide-react';
import { TraceEvent } from '../types/TraceEvent';

interface EventListProps {
  events: TraceEvent[];
  onEventSelect: (event: TraceEvent) => void;
  selectedEvent: TraceEvent | null;
}

export const EventList: React.FC<EventListProps> = ({
  events,
  onEventSelect,
  selectedEvent
}) => {
  const [searchTerm, setSearchTerm] = useState('');
  const [sortBy, setSortBy] = useState<'timestamp' | 'duration' | 'name'>('timestamp');
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('asc');

  const formatDuration = (microseconds: number): string => {
    if (microseconds < 1000) return `${microseconds.toFixed(0)}μs`;
    if (microseconds < 1000000) return `${(microseconds / 1000).toFixed(1)}ms`;
    return `${(microseconds / 1000000).toFixed(1)}s`;
  };

  const formatTimestamp = (timestamp: number): string => {
    return `${(timestamp / 1000).toFixed(3)}ms`;
  };

  const filteredAndSortedEvents = useMemo(() => {
    let filtered = events;
    
    if (searchTerm) {
      filtered = events.filter(event =>
        event.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
        event.cat.toLowerCase().includes(searchTerm.toLowerCase())
      );
    }

    return filtered.sort((a, b) => {
      let comparison = 0;
      
      switch (sortBy) {
        case 'timestamp':
          comparison = a.ts - b.ts;
          break;
        case 'duration':
          comparison = (a.dur || 0) - (b.dur || 0);
          break;
        case 'name':
          comparison = a.name.localeCompare(b.name);
          break;
      }
      
      return sortOrder === 'asc' ? comparison : -comparison;
    });
  }, [events, searchTerm, sortBy, sortOrder]);

  const eventTypeColors: Record<string, string> = {
    'B': 'bg-blue-500',
    'E': 'bg-green-500',
    'X': 'bg-yellow-500',
    'I': 'bg-purple-500',
    'P': 'bg-red-500',
    'C': 'bg-cyan-500',
    'M': 'bg-orange-500',
    'N': 'bg-lime-500',
    'D': 'bg-pink-500',
    'O': 'bg-indigo-500',
  };

  return (
    <div className="w-96 bg-gray-800 border-l border-gray-700 flex flex-col">
      <div className="p-4 border-b border-gray-700">
        <h2 className="text-lg font-semibold text-white mb-4 flex items-center">
          <List className="w-5 h-5 mr-2" />
          Event List ({filteredAndSortedEvents.length})
        </h2>
        
        {/* Search */}
        <div className="relative mb-4">
          <Search className="w-4 h-4 text-gray-400 absolute left-3 top-1/2 transform -translate-y-1/2" />
          <input
            type="text"
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            placeholder="Search events..."
            className="w-full pl-10 pr-4 py-2 bg-gray-700 text-white rounded border border-gray-600 focus:border-blue-500 focus:outline-none text-sm"
          />
        </div>

        {/* Sort Controls */}
        <div className="flex space-x-2">
          <select
            value={sortBy}
            onChange={(e) => setSortBy(e.target.value as any)}
            className="flex-1 px-3 py-2 bg-gray-700 text-white rounded border border-gray-600 focus:border-blue-500 focus:outline-none text-sm"
          >
            <option value="timestamp">Sort by Time</option>
            <option value="duration">Sort by Duration</option>
            <option value="name">Sort by Name</option>
          </select>
          
          <button
            onClick={() => setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc')}
            className="px-3 py-2 bg-gray-700 text-white rounded border border-gray-600 hover:bg-gray-600 transition-colors"
          >
            {sortOrder === 'asc' ? '↑' : '↓'}
          </button>
        </div>
      </div>

      {/* Event List */}
      <div className="flex-1 overflow-y-auto">
        {filteredAndSortedEvents.map((event, index) => {
          const isSelected = selectedEvent && 
            selectedEvent.pid === event.pid && 
            selectedEvent.tid === event.tid && 
            selectedEvent.ts === event.ts;

          return (
            <div
              key={`${event.pid}-${event.tid}-${event.ts}-${index}`}
              onClick={() => onEventSelect(event)}
              className={`p-3 border-b border-gray-700 cursor-pointer transition-colors hover:bg-gray-700 ${
                isSelected ? 'bg-blue-900 border-blue-600' : ''
              }`}
            >
              <div className="flex items-start justify-between mb-2">
                <div className="flex items-center space-x-2 flex-1 min-w-0">
                  <div className={`w-3 h-3 rounded-full ${eventTypeColors[event.ph] || 'bg-gray-500'}`} />
                  <div className="font-medium text-white truncate">{event.name}</div>
                </div>
                <div className="text-xs text-gray-400 ml-2">
                  {event.ph}
                </div>
              </div>
              
              <div className="text-sm text-gray-300 mb-1">
                Category: <span className="text-blue-400">{event.cat}</span>
              </div>
              
              <div className="flex items-center justify-between text-xs text-gray-400">
                <div className="flex items-center space-x-4">
                  <div className="flex items-center">
                    <Clock className="w-3 h-3 mr-1" />
                    {formatTimestamp(event.ts)}
                  </div>
                  {event.dur !== undefined && (
                    <div className="flex items-center">
                      <Zap className="w-3 h-3 mr-1" />
                      {formatDuration(event.dur)}
                    </div>
                  )}
                </div>
                <div>
                  P{event.pid} T{event.tid}
                </div>
              </div>
            </div>
          );
        })}
        
        {filteredAndSortedEvents.length === 0 && (
          <div className="p-8 text-center text-gray-400">
            <Filter className="w-12 h-12 mx-auto mb-4 opacity-50" />
            <p>No events match your search criteria</p>
          </div>
        )}
      </div>
    </div>
  );
};