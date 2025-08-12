import React, { useCallback } from 'react';
import { Upload, FileText } from 'lucide-react';

interface FileUploadProps {
  onFileLoad: (file: File) => void;
  isLoading: boolean;
}

export const FileUpload: React.FC<FileUploadProps> = ({ onFileLoad, isLoading }) => {
  const handleDrop = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    const files = Array.from(e.dataTransfer.files);
    const jsonFile = files.find(file => file.name.endsWith('.json'));
    if (jsonFile) {
      onFileLoad(jsonFile);
    }
  }, [onFileLoad]);

  const handleFileInput = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      onFileLoad(file);
    }
  }, [onFileLoad]);

  return (
    <div className="flex-1 flex items-center justify-center bg-gray-900">
      <div
        className="border-2 border-dashed border-gray-600 rounded-lg p-12 text-center hover:border-blue-500 transition-colors duration-200"
        onDrop={handleDrop}
        onDragOver={(e) => e.preventDefault()}
      >
        <div className="flex flex-col items-center space-y-4">
          {isLoading ? (
            <div className="animate-spin w-12 h-12 border-4 border-blue-500 border-t-transparent rounded-full"></div>
          ) : (
            <>
              <Upload className="w-16 h-16 text-gray-500" />
              <div>
                <h3 className="text-xl font-semibold text-white mb-2">
                  Upload Trace File
                </h3>
                <p className="text-gray-400 mb-4">
                  Drag and drop a JSON trace file or click to browse
                </p>
                <label className="inline-flex items-center px-6 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 cursor-pointer transition-colors">
                  <FileText className="w-5 h-5 mr-2" />
                  Choose File
                  <input
                    type="file"
                    accept=".json"
                    onChange={handleFileInput}
                    className="hidden"
                  />
                </label>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
};