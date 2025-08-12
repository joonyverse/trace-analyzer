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

  const eventColors: Record<string, string> = {
    'B': '#3B82F6', // Begin - Blue
    'E': '#10B981', // End - Green
    'X': '#F59E0B', // Complete - Yellow
    'I': '#8B5CF6', // Instant - Purple
    'P': '#EF4444', // Sample - Red
    'C': '#06B6D4', // Counter - Cyan
  };

  const drawTimeline = useCallback(() => {
    const canvas = canvasRef.current;
    const container = containerRef.current;
    if (!canvas || !container) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const rect = container.getBoundingClientRect();
    canvas.width = rect.width * window.devicePixelRatio;
    canvas.height = rect.height * window.devicePixelRatio;
    canvas.style.width = `${rect.width}px`;
    canvas.style.height = `${rect.height}px`;
    ctx.scale(window.devicePixelRatio, window.devicePixelRatio);

    const width = rect.width;
    const height = rect.height;
    const [startTime, endTime] = viewportRange;
    const timeScale = width / (endTime - startTime);

    // Clear canvas
    ctx.fillStyle = '#1F2937';
    ctx.fillRect(0, 0, width, height);

    // Group events by process and thread
    const processGroups = events.reduce((acc, event) => {
      const key = `${event.pid}-${event.tid}`;
      if (!acc[key]) {
        acc[key] = [];
      }
      acc[key].push(event);
      return acc;
    }, {} as Record<string, TraceEvent[]>);

    const trackHeight = 40;
    const trackSpacing = 5;
    let yOffset = 30;

    Object.entries(processGroups).forEach(([key, trackEvents]) => {
      const [pid, tid] = key.split('-');
      
      // Draw track header
      ctx.fillStyle = '#374151';
      ctx.fillRect(0, yOffset - 25, width, 25);
      ctx.fillStyle = '#D1D5DB';
      ctx.font = '12px sans-serif';
      ctx.textAlign = 'left';
      ctx.fillText(`P${pid} T${tid}`, 10, yOffset - 8);

      // Draw events
      trackEvents.forEach(event => {
        const x = (event.ts - startTime) * timeScale;
        const eventWidth = event.dur ? Math.max(1, event.dur * timeScale) : 2;
        
        if (x + eventWidth < 0 || x > width) return;

        const color = eventColors[event.ph] || '#6B7280';
        const isSelected = selectedEvent && 
          selectedEvent.pid === event.pid && 
          selectedEvent.tid === event.tid && 
          selectedEvent.ts === event.ts;

        ctx.fillStyle = isSelected ? '#FBBF24' : color;
        ctx.fillRect(x, yOffset, eventWidth, trackHeight - 5);

        // Draw event name if there's space
        if (eventWidth > 50) {
          ctx.fillStyle = '#FFFFFF';
          ctx.font = '10px sans-serif';
          ctx.textAlign = 'left';
          const text = event.name.substring(0, Math.floor(eventWidth / 6));
          ctx.fillText(text, x + 2, yOffset + 15);
        }
      });

      yOffset += trackHeight + trackSpacing;
    });

    // Draw time ruler
    ctx.fillStyle = '#374151';
    ctx.fillRect(0, 0, width, 25);
    
    const timeStep = Math.pow(10, Math.floor(Math.log10((endTime - startTime) / 10)));
    const stepPixels = timeStep * timeScale;
    
    if (stepPixels > 50) {
      for (let time = Math.ceil(startTime / timeStep) * timeStep; time < endTime; time += timeStep) {
        const x = (time - startTime) * timeScale;
        ctx.strokeStyle = '#6B7280';
        ctx.beginPath();
        ctx.moveTo(x, 20);
        ctx.lineTo(x, 25);
        ctx.stroke();
        
        ctx.fillStyle = '#D1D5DB';
        ctx.font = '10px monospace';
        ctx.textAlign = 'center';
        ctx.fillText(`${(time / 1000).toFixed(1)}ms`, x, 15);
      }
    }
  }, [events, viewportRange, selectedEvent]);

  useEffect(() => {
    drawTimeline();
  }, [drawTimeline]);

  useEffect(() => {
    const handleResize = () => drawTimeline();
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, [drawTimeline]);

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
    if (!isDragging || !dragStart) return;
    
    const rect = canvasRef.current?.getBoundingClientRect();
    if (!rect) return;

    const deltaX = e.clientX - dragStart.x;
    const timeRange = dragStart.range[1] - dragStart.range[0];
    const deltaTime = (deltaX / rect.width) * timeRange;
    
    const newStart = dragStart.range[0] - deltaTime;
    const newEnd = dragStart.range[1] - deltaTime;
    
    onViewportChange([newStart, newEnd]);
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
    const [startTime, endTime] = viewportRange;
    const timeScale = rect.width / (endTime - startTime);
    const clickTime = startTime + x / timeScale;

    // Find clicked event
    const trackHeight = 40;
    const trackSpacing = 5;
    let yOffset = 30;

    const processGroups = events.reduce((acc, event) => {
      const key = `${event.pid}-${event.tid}`;
      if (!acc[key]) {
        acc[key] = [];
      }
      acc[key].push(event);
      return acc;
    }, {} as Record<string, TraceEvent[]>);

    for (const [key, trackEvents] of Object.entries(processGroups)) {
      if (y >= yOffset && y < yOffset + trackHeight) {
        const clickedEvent = trackEvents.find(event => {
          const eventStart = event.ts;
          const eventEnd = event.ts + (event.dur || 0);
          return clickTime >= eventStart && clickTime <= eventEnd;
        });
        
        if (clickedEvent) {
          onEventSelect(clickedEvent);
          break;
        }
      }
      yOffset += trackHeight + trackSpacing;
    }
  };

  const handleWheel = (e: React.WheelEvent) => {
    e.preventDefault();
    
    const rect = canvasRef.current?.getBoundingClientRect();
    if (!rect) return;

    const mouseX = e.clientX - rect.left;
    const [startTime, endTime] = viewportRange;
    const mouseTime = startTime + (mouseX / rect.width) * (endTime - startTime);
    
    const zoomFactor = e.deltaY > 0 ? 1.1 : 0.9;
    const newRange = (endTime - startTime) * zoomFactor;
    
    const newStart = mouseTime - (mouseTime - startTime) * zoomFactor;
    const newEnd = newStart + newRange;
    
    onViewportChange([newStart, newEnd]);
  };

  return (
    <div 
      ref={containerRef}
      className="flex-1 bg-gray-900 overflow-hidden"
      style={{ cursor: isDragging ? 'grabbing' : 'grab' }}
    >
      <canvas
        ref={canvasRef}
        onMouseDown={handleMouseDown}
        onMouseMove={handleMouseMove}
        onMouseUp={handleMouseUp}
        onMouseLeave={handleMouseUp}
        onClick={handleClick}
        onWheel={handleWheel}
        className="w-full h-full"
      />
    </div>
  );
};