import React from 'react';
import { BarChart3, Clock, TrendingUp, Pi as Pie } from 'lucide-react';
import { Statistics } from '../types/TraceEvent';

interface StatisticsPanelProps {
  statistics: Statistics;
}

export const StatisticsPanel: React.FC<StatisticsPanelProps> = ({ statistics }) => {
  const formatDuration = (microseconds: number) => {
    if (microseconds < 1000) return `${microseconds.toFixed(1)}μs`;
    if (microseconds < 1000000) return `${(microseconds / 1000).toFixed(1)}ms`;
    return `${(microseconds / 1000000).toFixed(1)}s`;
  };

  const topCategories = Object.entries(statistics.categoryDistribution)
    .sort(([,a], [,b]) => b - a)
    .slice(0, 5);

  const topPhases = Object.entries(statistics.phaseDistribution)
    .sort(([,a], [,b]) => b - a)
    .slice(0, 5);

  return (
    <div className="w-80 bg-gray-800 border-l border-gray-700 p-4 overflow-y-auto">
      <h2 className="text-lg font-semibold text-white mb-4 flex items-center">
        <BarChart3 className="w-5 h-5 mr-2" />
        Statistics
      </h2>

      <div className="space-y-6">
        {/* Overview */}
        <div className="bg-gray-700 rounded-lg p-4">
          <h3 className="text-sm font-medium text-gray-300 mb-3 flex items-center">
            <TrendingUp className="w-4 h-4 mr-2" />
            Overview
          </h3>
          <div className="grid grid-cols-2 gap-4 text-sm">
            <div>
              <div className="text-gray-400">Total Events</div>
              <div className="text-white font-mono">{statistics.totalEvents.toLocaleString()}</div>
            </div>
            <div>
              <div className="text-gray-400">Avg Duration</div>
              <div className="text-white font-mono">{formatDuration(statistics.averageDuration)}</div>
            </div>
          </div>
        </div>

        {/* Duration Extremes */}
        <div className="bg-gray-700 rounded-lg p-4">
          <h3 className="text-sm font-medium text-gray-300 mb-3 flex items-center">
            <Clock className="w-4 h-4 mr-2" />
            Duration Extremes
          </h3>
          <div className="space-y-3 text-sm">
            {statistics.longestEvent && (
              <div>
                <div className="text-gray-400">Longest Event</div>
                <div className="text-white font-mono truncate">
                  {statistics.longestEvent.name}
                </div>
                <div className="text-blue-400 font-mono">
                  {formatDuration(statistics.longestEvent.dur || 0)}
                </div>
              </div>
            )}
            {statistics.shortestEvent && (
              <div>
                <div className="text-gray-400">Shortest Event</div>
                <div className="text-white font-mono truncate">
                  {statistics.shortestEvent.name}
                </div>
                <div className="text-green-400 font-mono">
                  {formatDuration(statistics.shortestEvent.dur || 0)}
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Category Distribution */}
        <div className="bg-gray-700 rounded-lg p-4">
          <h3 className="text-sm font-medium text-gray-300 mb-3 flex items-center">
            <Pie className="w-4 h-4 mr-2" />
            Top Categories
          </h3>
          <div className="space-y-2">
            {topCategories.map(([category, count]) => {
              const percentage = ((count / statistics.totalEvents) * 100).toFixed(1);
              return (
                <div key={category} className="flex items-center justify-between text-sm">
                  <div className="text-white truncate flex-1 mr-2">{category}</div>
                  <div className="text-gray-400 font-mono">{percentage}%</div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Phase Distribution */}
        <div className="bg-gray-700 rounded-lg p-4">
          <h3 className="text-sm font-medium text-gray-300 mb-3">Event Types</h3>
          <div className="space-y-2">
            {topPhases.map(([phase, count]) => {
              const percentage = ((count / statistics.totalEvents) * 100).toFixed(1);
              const phaseNames: Record<string, string> = {
                'B': 'Begin',
                'E': 'End',
                'X': 'Complete',
                'I': 'Instant',
                'P': 'Sample',
                'C': 'Counter'
              };
              return (
                <div key={phase} className="flex items-center justify-between text-sm">
                  <div className="text-white">{phaseNames[phase] || phase}</div>
                  <div className="text-gray-400 font-mono">{percentage}%</div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Process Distribution */}
        <div className="bg-gray-700 rounded-lg p-4">
          <h3 className="text-sm font-medium text-gray-300 mb-3">Process Distribution</h3>
          <div className="space-y-2 max-h-32 overflow-y-auto">
            {Object.entries(statistics.processDistribution)
              .sort(([,a], [,b]) => b - a)
              .slice(0, 10)
              .map(([pid, count]) => {
                const percentage = ((count / statistics.totalEvents) * 100).toFixed(1);
                return (
                  <div key={pid} className="flex items-center justify-between text-sm">
                    <div className="text-white">Process {pid}</div>
                    <div className="text-gray-400 font-mono">{percentage}%</div>
                  </div>
                );
              })}
          </div>
        </div>
      </div>
    </div>
  );
};