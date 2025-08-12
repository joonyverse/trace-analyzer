import React, { useRef, useEffect, useCallback } from 'react';
import { TraceEvent } from '../types/TraceEvent';

interface FlameGraphProps {
  events: TraceEvent[];
  selectedEvent: TraceEvent | null;
  onEventSelect: (event: TraceEvent) => void;
}

interface FlameNode {
  event: TraceEvent;
  children: FlameNode[];
  depth: number;
  x: number;
  width: number;
}

export const FlameGraph: React.FC<FlameGraphProps> = ({
  events,
  selectedEvent,
  onEventSelect
}) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  const buildFlameTree = useCallback((events: TraceEvent[]): FlameNode[] => {
    // Filter and sort events by timestamp
    const completeEvents = events
      .filter(e => e.ph === 'X' && e.dur && e.dur > 0)
      .sort((a, b) => a.ts - b.ts);

    const roots: FlameNode[] = [];
    const stack: FlameNode[] = [];

    completeEvents.forEach(event => {
      const node: FlameNode = {
        event,
        children: [],
        depth: 0,
        x: 0,
        width: 0
      };

      // Find parent (last event in stack that contains this event)
      while (stack.length > 0) {
        const parent = stack[stack.length - 1];
        const parentEnd = parent.event.ts + (parent.event.dur || 0);
        
        if (event.ts >= parent.event.ts && event.ts + (event.dur || 0) <= parentEnd) {
          // This event is contained within the parent
          parent.children.push(node);
          node.depth = parent.depth + 1;
          break;
        } else {
          // Parent has ended, remove from stack
          stack.pop();
        }
      }

      if (stack.length === 0) {
        // This is a root event
        roots.push(node);
        node.depth = 0;
      }

      stack.push(node);
    });

    return roots;
  }, []);

  const calculateLayout = useCallback((nodes: FlameNode[], totalWidth: number, startTime: number, endTime: number) => {
    const timeRange = endTime - startTime;
    
    const layoutNode = (node: FlameNode) => {
      const relativeStart = node.event.ts - startTime;
      const duration = node.event.dur || 0;
      
      node.x = (relativeStart / timeRange) * totalWidth;
      node.width = Math.max(1, (duration / timeRange) * totalWidth);
      
      node.children.forEach(layoutNode);
    };

    nodes.forEach(layoutNode);
  }, []);

  const drawFlameGraph = useCallback(() => {
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

    // Clear canvas
    ctx.fillStyle = '#111827';
    ctx.fillRect(0, 0, width, height);

    // Build flame tree
    const flameTree = buildFlameTree(events);
    if (flameTree.length === 0) return;

    // Calculate time range
    const startTime = Math.min(...events.map(e => e.ts));
    const endTime = Math.max(...events.map(e => e.ts + (e.dur || 0)));

    // Calculate layout
    calculateLayout(flameTree, width, startTime, endTime);

    // Find maximum depth for height calculation
    const findMaxDepth = (nodes: FlameNode[]): number => {
      let maxDepth = 0;
      nodes.forEach(node => {
        maxDepth = Math.max(maxDepth, node.depth);
        if (node.children.length > 0) {
          maxDepth = Math.max(maxDepth, findMaxDepth(node.children));
        }
      });
      return maxDepth;
    };

    const maxDepth = findMaxDepth(flameTree);
    const barHeight = Math.min(25, height / (maxDepth + 2));

    // Color palette for different categories
    const categoryColors: Record<string, string> = {
      'blink': '#FF6B6B',
      'v8': '#4ECDC4',
      'gpu': '#45B7D1',
      'renderer': '#96CEB4',
      'browser': '#FFEAA7',
      'loading': '#DDA0DD',
      'painting': '#98D8C8',
      'scripting': '#F7DC6F',
      'system': '#BB8FCE',
      'idle': '#85C1E9',
    };

    const getEventColor = (event: TraceEvent): string => {
      const category = event.cat.toLowerCase();
      for (const [key, color] of Object.entries(categoryColors)) {
        if (category.includes(key)) return color;
      }
      // Hash-based color for unknown categories
      let hash = 0;
      for (let i = 0; i < event.cat.length; i++) {
        hash = event.cat.charCodeAt(i) + ((hash << 5) - hash);
      }
      const hue = Math.abs(hash) % 360;
      return `hsl(${hue}, 70%, 60%)`;
    };

    // Draw flame graph
    const drawNode = (node: FlameNode) => {
      const y = height - (node.depth + 1) * barHeight - 10;
      const isSelected = selectedEvent && 
        selectedEvent.pid === node.event.pid && 
        selectedEvent.tid === node.event.tid && 
        selectedEvent.ts === node.event.ts;

      // Draw rectangle
      const color = getEventColor(node.event);
      ctx.fillStyle = isSelected ? '#FBBF24' : color;
      ctx.fillRect(node.x, y, node.width, barHeight - 1);

      // Draw border for selected event
      if (isSelected) {
        ctx.strokeStyle = '#F59E0B';
        ctx.lineWidth = 2;
        ctx.strokeRect(node.x, y, node.width, barHeight - 1);
      }

      // Draw text if there's enough space
      if (node.width > 30) {
        ctx.fillStyle = '#000000';
        ctx.font = '11px sans-serif';
        ctx.textAlign = 'left';
        
        const maxChars = Math.floor(node.width / 7);
        const text = node.event.name.length > maxChars ? 
          node.event.name.substring(0, maxChars - 3) + '...' : 
          node.event.name;
        
        // Add text shadow for better readability
        ctx.fillStyle = '#FFFFFF';
        ctx.fillText(text, node.x + 2, y + 15);
        ctx.fillStyle = '#000000';
        ctx.fillText(text, node.x + 1, y + 14);
      }

      // Draw children
      node.children.forEach(drawNode);
    };

    flameTree.forEach(drawNode);

    // Draw legend
    drawLegend(ctx, width, height, categoryColors);

  }, [events, selectedEvent, buildFlameTree, calculateLayout]);

  const drawLegend = (ctx: CanvasRenderingContext2D, width: number, height: number, categoryColors: Record<string, string>) => {
    const legendY = 10;
    const legendItemWidth = 80;
    const legendItemHeight = 20;
    let legendX = 10;

    ctx.fillStyle = 'rgba(0, 0, 0, 0.7)';
    ctx.fillRect(5, 5, width - 10, 30);

    Object.entries(categoryColors).forEach(([category, color]) => {
      if (legendX + legendItemWidth > width - 10) return;

      // Draw color box
      ctx.fillStyle = color;
      ctx.fillRect(legendX, legendY, 15, 15);

      // Draw text
      ctx.fillStyle = '#FFFFFF';
      ctx.font = '10px sans-serif';
      ctx.textAlign = 'left';
      ctx.fillText(category, legendX + 20, legendY + 12);

      legendX += legendItemWidth;
    });
  };

  const getEventAtPosition = (x: number, y: number): TraceEvent | null => {
    const rect = containerRef.current?.getBoundingClientRect();
    if (!rect) return null;

    const flameTree = buildFlameTree(events);
    if (flameTree.length === 0) return null;

    const startTime = Math.min(...events.map(e => e.ts));
    const endTime = Math.max(...events.map(e => e.ts + (e.dur || 0)));
    calculateLayout(flameTree, rect.width, startTime, endTime);

    const findMaxDepth = (nodes: FlameNode[]): number => {
      let maxDepth = 0;
      nodes.forEach(node => {
        maxDepth = Math.max(maxDepth, node.depth);
        if (node.children.length > 0) {
          maxDepth = Math.max(maxDepth, findMaxDepth(node.children));
        }
      });
      return maxDepth;
    };

    const maxDepth = findMaxDepth(flameTree);
    const barHeight = Math.min(25, rect.height / (maxDepth + 2));

    const checkNode = (node: FlameNode): TraceEvent | null => {
      const nodeY = rect.height - (node.depth + 1) * barHeight - 10;
      
      if (x >= node.x && x <= node.x + node.width && 
          y >= nodeY && y <= nodeY + barHeight - 1) {
        return node.event;
      }

      for (const child of node.children) {
        const result = checkNode(child);
        if (result) return result;
      }

      return null;
    };

    for (const root of flameTree) {
      const result = checkNode(root);
      if (result) return result;
    }

    return null;
  };

  useEffect(() => {
    drawFlameGraph();
  }, [drawFlameGraph]);

  const handleClick = (e: React.MouseEvent) => {
    const rect = containerRef.current?.getBoundingClientRect();
    if (!rect) return;

    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    
    const clickedEvent = getEventAtPosition(x, y);
    if (clickedEvent) {
      onEventSelect(clickedEvent);
    }
  };

  return (
    <div 
      ref={containerRef}
      className="w-full h-64 bg-gray-900 border border-gray-700 rounded-lg overflow-hidden"
    >
      <canvas
        ref={canvasRef}
        onClick={handleClick}
        className="w-full h-full cursor-pointer"
      />
    </div>
  );
};