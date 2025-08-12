import React, { useState } from 'react';
import { Header } from './components/Header';
import { FileUpload } from './components/FileUpload';
import { FilterPanel } from './components/FilterPanel';
import { Timeline } from './components/Timeline';
import { StatisticsPanel } from './components/StatisticsPanel';
import { EventInspector } from './components/EventInspector';
import { useTraceData } from './hooks/useTraceData';

function App() {
  const [isFilterPanelOpen, setIsFilterPanelOpen] = useState(true);
  const {
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
  } = useTraceData();

  const handleExport = () => {
    if (!filteredEvents.length) return;
    
    const exportData = {
      events: filteredEvents,
      statistics,
      filters,
      metadata: traceData?.metadata
    };
    
    const blob = new Blob([JSON.stringify(exportData, null, 2)], {
      type: 'application/json'
    });
    
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'trace-analysis.json';
    a.click();
    URL.revokeObjectURL(url);
  };

  if (!traceData) {
    return (
      <div className="min-h-screen bg-gray-900 flex flex-col">
        <Header onExport={handleExport} />
        <FileUpload onFileLoad={loadTraceFile} isLoading={isLoading} />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-900 flex flex-col">
      <Header onExport={handleExport} />
      
      <div className="flex-1 flex">
        <FilterPanel
          filters={filters}
          traceData={traceData}
          onFiltersChange={setFilters}
          isOpen={isFilterPanelOpen}
          onToggle={() => setIsFilterPanelOpen(!isFilterPanelOpen)}
        />
        
        <Timeline
          events={visibleEvents}
          viewportRange={viewportRange}
          onViewportChange={setViewportRange}
          onEventSelect={setSelectedEvent}
          selectedEvent={selectedEvent}
        />
        
        <StatisticsPanel statistics={statistics} />
      </div>

      <EventInspector
        event={selectedEvent}
        onClose={() => setSelectedEvent(null)}
      />
      
      {/* Status Bar */}
      <div className="bg-gray-800 border-t border-gray-700 px-4 py-2 text-sm text-gray-400 flex justify-between">
        <div>
          Showing {visibleEvents.length.toLocaleString()} of {filteredEvents.length.toLocaleString()} events
        </div>
        <div>
          Viewport: {((viewportRange[1] - viewportRange[0]) / 1000).toFixed(2)}ms range
        </div>
      </div>
    </div>
  );
}

export default App;