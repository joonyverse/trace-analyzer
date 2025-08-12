import React, { useRef, useEffect, useState, useCallback } from 'react';
import { TraceEvent } from '../types/TraceEvent';

interface TimelineProps {
  events: TraceEvent[];
  viewportRange: [number, number];
  onViewportChange: (range: [number, number]) => void;
  onEventSelect: (event: TraceEvent) => void;
  selectedEvent: TraceEvent | null;
}

export const Timeline: React.FC<TimelineProps> = ({
  events,
  viewportRange,
  onViewportChange,
  onEventSelect,
  selectedEvent
}) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const [isDragging, setIsDragging] = useState(false);
  const [dragStart, setDragStart] = useState<{ x: number; range: [number, number] } | null>(null);
  const [hoveredEvent, setHoveredEvent] = useState<TraceEvent | null>(null);

  const eventColors: Record<string, string> = {
    'B': '#3B82F6', // Begin - Blue
    'E': '#10B981', // End - Green
    'X': '#F59E0B', // Complete - Yellow
    'I': '#8B5CF6', // Instant - Purple
    'P': '#EF4444', // Sample - Red
    'C': '#06B6D4', // Counter - Cyan
    'M': '#F97316', // Metadata - Orange
    'N': '#84CC16', // Object - Lime
    'D': '#EC4899', // Object Destroyed - Pink
    'O': '#6366F1', // Object Snapshot - Indigo
  };

  const drawTimeline = useCallback(() => {
    const canvas = canvasRef.current;
    const container = containerRef.current;
    if (!canvas || !container || events.length === 0) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const rect = container.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    
    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;
    canvas.style.width = `${rect.width}px`;
    canvas.style.height = `${rect.height}px`;
    ctx.scale(dpr, dpr);

    const width = rect.width;
    const height = rect.height;
    const [startTime, endTime] = viewportRange;
    const timeRange = endTime - startTime;
    const timeScale = width / timeRange;

    // Clear canvas with dark background
    ctx.fillStyle = '#111827';
    ctx.fillRect(0, 0, width, height);

    // Group events by process and thread
    const processGroups = events.reduce((acc, event) => {
      const key = `${event.pid}-${event.tid}`;
      if (!acc[key]) {
        acc[key] = {
          pid: event.pid,
          tid: event.tid,
          events: []
        };
      }
      acc[key].events.push(event);
      return acc;
    }, {} as Record<string, { pid: number; tid: number; events: TraceEvent[] }>);

    const trackHeight = 50;
    const trackSpacing = 2;
    const headerHeight = 30;
    let yOffset = headerHeight;

    // Draw time ruler
    ctx.fillStyle = '#1F2937';
    ctx.fillRect(0, 0, width, headerHeight);
    
    // Calculate appropriate time step
    const minStepPixels = 80;
    const timeStep = Math.pow(10, Math.floor(Math.log10(timeRange / (width / minStepPixels))));
    const stepPixels = timeStep * timeScale;
    
    if (stepPixels > 20) {
      ctx.strokeStyle = '#374151';
      ctx.lineWidth = 1;
      
      for (let time = Math.ceil(startTime / timeStep) * timeStep; time <= endTime; time += timeStep) {
        const x = (time - startTime) * timeScale;
        
        // Draw tick
        ctx.beginPath();
        ctx.moveTo(x, headerHeight - 10);
        ctx.lineTo(x, headerHeight);
        ctx.stroke();
        
        // Draw time label
        ctx.fillStyle = '#D1D5DB';
        ctx.font = '11px monospace';
        ctx.textAlign = 'center';
        const timeMs = (time - startTime) / 1000;
        ctx.fillText(`${timeMs.toFixed(1)}ms`, x, headerHeight - 15);
      }
    }

    // Draw tracks
    Object.entries(processGroups).forEach(([key, group]) => {
      const trackY = yOffset;
      
      // Draw track background
      ctx.fillStyle = yOffset % (trackHeight * 2 + trackSpacing * 2) < trackHeight + trackSpacing ? '#1F2937' : '#111827';
      ctx.fillRect(0, trackY, width, trackHeight);
      
      // Draw track header
      ctx.fillStyle = '#374151';
      ctx.fillRect(0, trackY, 120, trackHeight);
      
      // Track label
      ctx.fillStyle = '#E5E7EB';
      ctx.font = '12px sans-serif';
      ctx.textAlign = 'left';
      ctx.fillText(`P${group.pid}`, 8, trackY + 18);
      ctx.fillStyle = '#9CA3AF';
      ctx.font = '10px sans-serif';
      ctx.fillText(`T${group.tid}`, 8, trackY + 32);
      
      // Draw events for this track
      group.events.forEach(event => {
        if (event.ts > endTime || (event.ts + (event.dur || 0)) < startTime) return;
        
        const eventStart = Math.max(startTime, event.ts);
        const eventEnd = Math.min(endTime, event.ts + (event.dur || 1000));
        const x = (eventStart - startTime) * timeScale;
        const eventWidth = Math.max(1, (eventEnd - eventStart) * timeScale);
        
        const color = eventColors[event.ph] || '#6B7280';
        const isSelected = selectedEvent && 
          selectedEvent.pid === event.pid && 
          selectedEvent.tid === event.tid && 
          selectedEvent.ts === event.ts;
        const isHovered = hoveredEvent && 
          hoveredEvent.pid === event.pid && 
          hoveredEvent.tid === event.tid && 
          hoveredEvent.ts === event.ts;

        // Draw event rectangle
        ctx.fillStyle = isSelected ? '#FBBF24' : isHovered ? '#60A5FA' : color;
        const eventHeight = 35;
        const eventY = trackY + (trackHeight - eventHeight) / 2;
        
        // Add subtle gradient for better visual appeal
        if (eventWidth > 2) {
          const gradient = ctx.createLinearGradient(x, eventY, x, eventY + eventHeight);
          gradient.addColorStop(0, isSelected ? '#FBBF24' : isHovered ? '#60A5FA' : color);
          gradient.addColorStop(1, isSelected ? '#F59E0B' : isHovered ? '#3B82F6' : adjustBrightness(color, -20));
          ctx.fillStyle = gradient;
        }
        
        ctx.fillRect(x, eventY, eventWidth, eventHeight);
        
        // Draw border for selected/hovered events
        if (isSelected || isHovered) {
          ctx.strokeStyle = isSelected ? '#F59E0B' : '#3B82F6';
          ctx.lineWidth = 2;
          ctx.strokeRect(x, eventY, eventWidth, eventHeight);
        }

        // Draw event name if there's enough space
        if (eventWidth > 40) {
          ctx.fillStyle = '#FFFFFF';
          ctx.font = '10px sans-serif';
          ctx.textAlign = 'left';
          const maxChars = Math.floor(eventWidth / 6);
          const text = event.name.length > maxChars ? 
            event.name.substring(0, maxChars - 3) + '...' : 
            event.name;
          ctx.fillText(text, x + 4, eventY + 20);
        }
        
        // Draw duration if available and space permits
        if (event.dur && eventWidth > 60) {
          ctx.fillStyle = '#D1D5DB';
          ctx.font = '9px monospace';
          const durationText = formatDuration(event.dur);
          ctx.fillText(durationText, x + 4, eventY + 32);
        }
      });

      yOffset += trackHeight + trackSpacing;
    });

    // Draw minimap
    drawMinimap(ctx, width, height, events, viewportRange, startTime, endTime);

  }, [events, viewportRange, selectedEvent, hoveredEvent]);

  const drawMinimap = (ctx: CanvasRenderingContext2D, width: number, height: number, events: TraceEvent[], viewportRange: [number, number], globalStart: number, globalEnd: number) => {
    const minimapHeight = 60;
    const minimapY = height - minimapHeight - 10;
    const minimapWidth = width - 20;
    const minimapX = 10;
    
    // Draw minimap background
    ctx.fillStyle = '#1F2937';
    ctx.fillRect(minimapX, minimapY, minimapWidth, minimapHeight);
    ctx.strokeStyle = '#374151';
    ctx.strokeRect(minimapX, minimapY, minimapWidth, minimapHeight);
    
    // Draw events in minimap
    const globalTimeRange = globalEnd - globalStart;
    const minimapScale = minimapWidth / globalTimeRange;
    
    events.forEach(event => {
      const x = minimapX + (event.ts - globalStart) * minimapScale;
      const eventWidth = Math.max(1, (event.dur || 1000) * minimapScale);
      const color = eventColors[event.ph] || '#6B7280';
      
      ctx.fillStyle = color;
      ctx.fillRect(x, minimapY + 10, eventWidth, minimapHeight - 20);
    });
    
    // Draw viewport indicator
    const viewportStart = minimapX + (viewportRange[0] - globalStart) * minimapScale;
    const viewportWidth = (viewportRange[1] - viewportRange[0]) * minimapScale;
    
    ctx.fillStyle = 'rgba(59, 130, 246, 0.3)';
    ctx.fillRect(viewportStart, minimapY, viewportWidth, minimapHeight);
    ctx.strokeStyle = '#3B82F6';
    ctx.lineWidth = 2;
    ctx.strokeRect(viewportStart, minimapY, viewportWidth, minimapHeight);
  };

  const adjustBrightness = (color: string, amount: number): string => {
    const hex = color.replace('#', '');
    const r = Math.max(0, Math.min(255, parseInt(hex.substr(0, 2), 16) + amount));
    const g = Math.max(0, Math.min(255, parseInt(hex.substr(2, 2), 16) + amount));
    const b = Math.max(0, Math.min(255, parseInt(hex.substr(4, 2), 16) + amount));
    return `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`;
  };

  const formatDuration = (microseconds: number): string => {
    if (microseconds < 1000) return `${microseconds.toFixed(0)}μs`;
    if (microseconds < 1000000) return `${(microseconds / 1000).toFixed(1)}ms`;
    return `${(microseconds / 1000000).toFixed(1)}s`;
  };

  useEffect(() => {
    drawTimeline();
  }, [drawTimeline]);

  useEffect(() => {
    const handleResize = () => {
      setTimeout(drawTimeline, 0);
    };
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, [drawTimeline]);

  const getEventAtPosition = (x: number, y: number): TraceEvent | null => {
    const rect = canvasRef.current?.getBoundingClientRect();
    if (!rect) return null;

    const [startTime, endTime] = viewportRange;
    const timeScale = rect.width / (endTime - startTime);
    const clickTime = startTime + x / timeScale;

    const trackHeight = 50;
    const trackSpacing = 2;
    const headerHeight = 30;
    let yOffset = headerHeight;

    const processGroups = events.reduce((acc, event) => {
      const key = `${event.pid}-${event.tid}`;
      if (!acc[key]) {
        acc[key] = { pid: event.pid, tid: event.tid, events: [] };
      }
      acc[key].events.push(event);
      return acc;
    }, {} as Record<string, { pid: number; tid: number; events: TraceEvent[] }>);

    for (const [key, group] of Object.entries(processGroups)) {
      if (y >= yOffset && y < yOffset + trackHeight) {
        const clickedEvent = group.events.find(event => {
          const eventStart = event.ts;
          const eventEnd = event.ts + (event.dur || 1000);
          return clickTime >= eventStart && clickTime <= eventEnd;
        });
        
        if (clickedEvent) {
          return clickedEvent;
        }
      }
      yOffset += trackHeight + trackSpacing;
    }

    return null;
  };

  const handleMouseDown = (e: React.MouseEvent) => {
    const rect = canvasRef.current?.getBoundingClientRect();
    if (!rect) return;
    
    setIsDragging(true);
    setDragStart({
      x: e.clientX,
      range: [...viewportRange]
    });
  };

  const handleMouseMove = (e: React.MouseEvent) => {
    const rect = canvasRef.current?.getBoundingClientRect();
    if (!rect) return;

    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;

    if (isDragging && dragStart) {
      const deltaX = e.clientX - dragStart.x;
      const timeRange = dragStart.range[1] - dragStart.range[0];
      const deltaTime = (deltaX / rect.width) * timeRange;
      
      const newStart = dragStart.range[0] - deltaTime;
      const newEnd = dragStart.range[1] - deltaTime;
      
      onViewportChange([newStart, newEnd]);
    } else {
      // Handle hover
      const hoveredEvent = getEventAtPosition(x, y);
      setHoveredEvent(hoveredEvent);
    }
  };

  const handleMouseUp = () => {
    setIsDragging(false);
    setDragStart(null);
  };

  const handleClick = (e: React.MouseEvent) => {
    if (isDragging) return;
    
    const rect = canvasRef.current?.getBoundingClientRect();
    if (!rect) return;

    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    
    const clickedEvent = getEventAtPosition(x, y);
    if (clickedEvent) {
      onEventSelect(clickedEvent);
    }
  };

  const handleWheel = (e: React.WheelEvent) => {
    e.preventDefault();
    
    const rect = canvasRef.current?.getBoundingClientRect();
    if (!rect) return;

    const mouseX = e.clientX - rect.left;
    const [startTime, endTime] = viewportRange;
    const mouseTime = startTime + (mouseX / rect.width) * (endTime - startTime);
    
    const zoomFactor = e.deltaY > 0 ? 1.2 : 0.8;
    const newRange = (endTime - startTime) * zoomFactor;
    
    const newStart = mouseTime - (mouseTime - startTime) * zoomFactor;
    const newEnd = newStart + newRange;
    
    onViewportChange([newStart, newEnd]);
  };

  return (
    <div 
      ref={containerRef}
      className="flex-1 bg-gray-900 overflow-hidden relative"
      style={{ cursor: isDragging ? 'grabbing' : 'grab' }}
    >
      <canvas
        ref={canvasRef}
        onMouseDown={handleMouseDown}
        onMouseMove={handleMouseMove}
        onMouseUp={handleMouseUp}
        onMouseLeave={() => {
          handleMouseUp();
          setHoveredEvent(null);
        }}
        onClick={handleClick}
        onWheel={handleWheel}
        className="w-full h-full"
      />
      
      {/* Tooltip for hovered event */}
      {hoveredEvent && (
        <div className="absolute pointer-events-none bg-gray-800 text-white p-2 rounded shadow-lg text-sm z-10"
             style={{ 
               left: '50%', 
               top: '10px',
               transform: 'translateX(-50%)'
             }}>
          <div className="font-semibold">{hoveredEvent.name}</div>
          <div className="text-gray-300">
            {hoveredEvent.dur ? formatDuration(hoveredEvent.dur) : 'Instant'}
          </div>
          <div className="text-gray-400 text-xs">
            P{hoveredEvent.pid} T{hoveredEvent.tid}
          </div>
        </div>
      )}
    </div>
  );
};