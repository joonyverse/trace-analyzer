import React from 'react';
import { Activity, Download, Settings, Search, BarChart3, Flame } from 'lucide-react';

interface HeaderProps {
  onExport?: () => void;
  onSettings?: () => void;
  activeView?: 'timeline' | 'flamegraph';
  onViewChange?: (view: 'timeline' | 'flamegraph') => void;
}

export const Header: React.FC<HeaderProps> = ({ 
  onExport, 
  onSettings, 
  activeView = 'timeline',
  onViewChange 
}) => {
  return (
    <header className="bg-gray-800 border-b border-gray-700 px-6 py-4">
      <div className="flex items-center justify-between">
        <div className="flex items-center space-x-3">
          <Activity className="w-8 h-8 text-blue-500" />
          <div>
            <h1 className="text-xl font-bold text-white">TraceViz Pro</h1>
            <p className="text-sm text-gray-400">Advanced Performance Analysis</p>
          </div>
        </div>
        
        <div className="flex items-center space-x-4">
          {/* View Toggle */}
          {onViewChange && (
            <div className="flex bg-gray-700 rounded-lg p-1">
              <button
                onClick={() => onViewChange('timeline')}
                className={`flex items-center space-x-2 px-3 py-2 rounded-md transition-colors ${
                  activeView === 'timeline' 
                    ? 'bg-blue-600 text-white' 
                    : 'text-gray-300 hover:text-white'
                }`}
              >
                <BarChart3 className="w-4 h-4" />
                <span>Timeline</span>
              </button>
              <button
                onClick={() => onViewChange('flamegraph')}
                className={`flex items-center space-x-2 px-3 py-2 rounded-md transition-colors ${
                  activeView === 'flamegraph' 
                    ? 'bg-blue-600 text-white' 
                    : 'text-gray-300 hover:text-white'
                }`}
              >
                <Flame className="w-4 h-4" />
                <span>Flame Graph</span>
              </button>
            </div>
          )}
          
          <div className="relative">
            <Search className="w-5 h-5 text-gray-400 absolute left-3 top-1/2 transform -translate-y-1/2" />
            <input
              type="text"
              placeholder="Search events..."
              className="pl-10 pr-4 py-2 bg-gray-700 text-white rounded-lg border border-gray-600 focus:border-blue-500 focus:outline-none"
            />
          </div>
          
          <button
            onClick={onExport}
            className="flex items-center space-x-2 px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 transition-colors"
          >
            <Download className="w-4 h-4" />
            <span>Export</span>
          </button>
          
          <button
            onClick={onSettings}
            className="p-2 text-gray-400 hover:text-white transition-colors"
          >
            <Settings className="w-5 h-5" />
          </button>
        </div>
      </div>
    </header>
  );
};