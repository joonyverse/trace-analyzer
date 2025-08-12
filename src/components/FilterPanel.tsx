import React from 'react';
import { Filter, X, ChevronDown } from 'lucide-react';
import { FilterCriteria, TraceData } from '../types/TraceEvent';

interface FilterPanelProps {
  filters: FilterCriteria;
  traceData: TraceData | null;
  onFiltersChange: (filters: FilterCriteria) => void;
  isOpen: boolean;
  onToggle: () => void;
}

export const FilterPanel: React.FC<FilterPanelProps> = ({
  filters,
  traceData,
  onFiltersChange,
  isOpen,
  onToggle
}) => {
  if (!traceData) return null;

  const allCategories = Array.from(new Set(
    traceData.processes.flatMap(p => 
      p.threads.flatMap(t => t.events.map(e => e.cat))
    )
  ));

  const allPhases = Array.from(new Set(
    traceData.processes.flatMap(p => 
      p.threads.flatMap(t => t.events.map(e => e.ph))
    )
  ));

  return (
    <div className={`bg-gray-800 border-r border-gray-700 transition-all duration-300 ${
      isOpen ? 'w-80' : 'w-12'
    }`}>
      <div className="p-4">
        <button
          onClick={onToggle}
          className="flex items-center justify-between w-full text-white hover:text-blue-400 transition-colors"
        >
          <div className="flex items-center space-x-2">
            <Filter className="w-5 h-5" />
            {isOpen && <span className="font-semibold">Filters</span>}
          </div>
          {isOpen && <ChevronDown className={`w-4 h-4 transition-transform ${isOpen ? 'rotate-180' : ''}`} />}
        </button>
      </div>

      {isOpen && (
        <div className="px-4 pb-4 space-y-6">
          {/* Search */}
          <div>
            <label className="block text-sm font-medium text-gray-300 mb-2">
              Search Events
            </label>
            <input
              type="text"
              value={filters.searchTerm || ''}
              onChange={(e) => onFiltersChange({ ...filters, searchTerm: e.target.value })}
              placeholder="Filter by name..."
              className="w-full px-3 py-2 bg-gray-700 text-white rounded border border-gray-600 focus:border-blue-500 focus:outline-none"
            />
          </div>

          {/* Duration Range */}
          <div>
            <label className="block text-sm font-medium text-gray-300 mb-2">
              Duration Range (μs)
            </label>
            <div className="grid grid-cols-2 gap-2">
              <input
                type="number"
                value={filters.minDuration || ''}
                onChange={(e) => onFiltersChange({ 
                  ...filters, 
                  minDuration: e.target.value ? Number(e.target.value) : undefined 
                })}
                placeholder="Min"
                className="px-3 py-2 bg-gray-700 text-white rounded border border-gray-600 focus:border-blue-500 focus:outline-none"
              />
              <input
                type="number"
                value={filters.maxDuration || ''}
                onChange={(e) => onFiltersChange({ 
                  ...filters, 
                  maxDuration: e.target.value ? Number(e.target.value) : undefined 
                })}
                placeholder="Max"
                className="px-3 py-2 bg-gray-700 text-white rounded border border-gray-600 focus:border-blue-500 focus:outline-none"
              />
            </div>
          </div>

          {/* Categories */}
          <div>
            <label className="block text-sm font-medium text-gray-300 mb-2">
              Categories
            </label>
            <div className="max-h-32 overflow-y-auto space-y-1">
              {allCategories.map(category => (
                <label key={category} className="flex items-center text-sm text-gray-300">
                  <input
                    type="checkbox"
                    checked={filters.categories?.includes(category) || false}
                    onChange={(e) => {
                      const categories = filters.categories || [];
                      const newCategories = e.target.checked
                        ? [...categories, category]
                        : categories.filter(c => c !== category);
                      onFiltersChange({ ...filters, categories: newCategories });
                    }}
                    className="mr-2 rounded"
                  />
                  {category}
                </label>
              ))}
            </div>
          </div>

          {/* Event Types */}
          <div>
            <label className="block text-sm font-medium text-gray-300 mb-2">
              Event Types
            </label>
            <div className="space-y-1">
              {allPhases.map(phase => (
                <label key={phase} className="flex items-center text-sm text-gray-300">
                  <input
                    type="checkbox"
                    checked={filters.eventTypes?.includes(phase) || false}
                    onChange={(e) => {
                      const eventTypes = filters.eventTypes || [];
                      const newEventTypes = e.target.checked
                        ? [...eventTypes, phase]
                        : eventTypes.filter(t => t !== phase);
                      onFiltersChange({ ...filters, eventTypes: newEventTypes });
                    }}
                    className="mr-2 rounded"
                  />
                  {phase}
                </label>
              ))}
            </div>
          </div>

          {/* Clear Filters */}
          <button
            onClick={() => onFiltersChange({})}
            className="w-full flex items-center justify-center space-x-2 px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700 transition-colors"
          >
            <X className="w-4 h-4" />
            <span>Clear All</span>
          </button>
        </div>
      )}
    </div>
  );
};