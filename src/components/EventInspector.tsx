import React from 'react';
import { Eye, X } from 'lucide-react';
import { TraceEvent } from '../types/TraceEvent';

interface EventInspectorProps {
  event: TraceEvent | null;
  onClose: () => void;
}

export const EventInspector: React.FC<EventInspectorProps> = ({ event, onClose }) => {
  if (!event) return null;

  const formatDuration = (microseconds: number) => {
    if (microseconds < 1000) return `${microseconds.toFixed(1)}μs`;
    if (microseconds < 1000000) return `${(microseconds / 1000).toFixed(1)}ms`;
    return `${(microseconds / 1000000).toFixed(1)}s`;
  };

  const formatTimestamp = (timestamp: number) => {
    return `${(timestamp / 1000).toFixed(3)}ms`;
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
      <div className="bg-gray-800 rounded-lg max-w-2xl w-full max-h-[80vh] overflow-auto">
        <div className="flex items-center justify-between p-4 border-b border-gray-700">
          <h2 className="text-lg font-semibold text-white flex items-center">
            <Eye className="w-5 h-5 mr-2" />
            Event Inspector
          </h2>
          <button
            onClick={onClose}
            className="p-1 text-gray-400 hover:text-white transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        <div className="p-4 space-y-4">
          {/* Basic Info */}
          <div className="bg-gray-700 rounded-lg p-4">
            <h3 className="text-sm font-medium text-gray-300 mb-3">Basic Information</h3>
            <div className="grid grid-cols-2 gap-4 text-sm">
              <div>
                <div className="text-gray-400">Name</div>
                <div className="text-white font-mono break-all">{event.name}</div>
              </div>
              <div>
                <div className="text-gray-400">Category</div>
                <div className="text-white font-mono">{event.cat}</div>
              </div>
              <div>
                <div className="text-gray-400">Phase</div>
                <div className="text-white font-mono">{event.ph}</div>
              </div>
              <div>
                <div className="text-gray-400">Process ID</div>
                <div className="text-white font-mono">{event.pid}</div>
              </div>
              <div>
                <div className="text-gray-400">Thread ID</div>
                <div className="text-white font-mono">{event.tid}</div>
              </div>
              <div>
                <div className="text-gray-400">Timestamp</div>
                <div className="text-white font-mono">{formatTimestamp(event.ts)}</div>
              </div>
              {event.dur !== undefined && (
                <div>
                  <div className="text-gray-400">Duration</div>
                  <div className="text-white font-mono">{formatDuration(event.dur)}</div>
                </div>
              )}
              {event.id && (
                <div>
                  <div className="text-gray-400">ID</div>
                  <div className="text-white font-mono">{event.id}</div>
                </div>
              )}
            </div>
          </div>

          {/* Arguments */}
          {event.args && Object.keys(event.args).length > 0 && (
            <div className="bg-gray-700 rounded-lg p-4">
              <h3 className="text-sm font-medium text-gray-300 mb-3">Arguments</h3>
              <div className="space-y-2">
                {Object.entries(event.args).map(([key, value]) => (
                  <div key={key} className="text-sm">
                    <div className="text-gray-400">{key}</div>
                    <div className="text-white font-mono bg-gray-800 p-2 rounded break-all">
                      {typeof value === 'object' ? JSON.stringify(value, null, 2) : String(value)}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Stack Trace */}
          {event.stack && event.stack.length > 0 && (
            <div className="bg-gray-700 rounded-lg p-4">
              <h3 className="text-sm font-medium text-gray-300 mb-3">Stack Trace</h3>
              <div className="bg-gray-800 p-3 rounded font-mono text-sm text-white max-h-40 overflow-y-auto">
                {event.stack.map((frame: any, index: number) => (
                  <div key={index} className="mb-1">
                    {typeof frame === 'object' ? JSON.stringify(frame) : String(frame)}
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Raw Data */}
          <div className="bg-gray-700 rounded-lg p-4">
            <h3 className="text-sm font-medium text-gray-300 mb-3">Raw Event Data</h3>
            <div className="bg-gray-800 p-3 rounded">
              <pre className="text-xs text-white overflow-x-auto">
                {JSON.stringify(event, null, 2)}
              </pre>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};