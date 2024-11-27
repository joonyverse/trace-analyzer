import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:math';
import 'timeline_chart.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';
import 'dart:isolate';
import 'config.dart';

class TraceAnalyzer {
  List<dynamic> events = [];

  // 청크 단위로 처리할 이벤트 수
  static const int _chunkSize = TraceViewerConfig.chunkSize;

  Future<Map<String, dynamic>> parseTraceFile(String fileContent) async {
    final stopwatch = Stopwatch()..start();
    print('시작: 파일 파싱');
    
    try {
      final splitTime = stopwatch.elapsedMilliseconds;
      final lines = fileContent.split('\n');
      print('라인 분할 시간: ${stopwatch.elapsedMilliseconds - splitTime}ms');
      
      events = [];
      List<dynamic> parsedEvents = [];
      
      // 청크 처리 시작 시간
      final chunkStartTime = stopwatch.elapsedMilliseconds;
      int totalLines = 0;
      
      for (var i = 0; i < lines.length; i += _chunkSize) {
        final chunkTime = stopwatch.elapsedMilliseconds;
        
        final end = (i + _chunkSize < lines.length) ? i + _chunkSize : lines.length;
        final chunk = lines.sublist(i, end);
        
        // 각 라인 파싱
        for (var line in chunk) {
          if (line.trim().isEmpty || line.trim() == '[' || line.trim() == ']') continue;
          
          var cleanLine = line.trim();
          if (cleanLine.endsWith(',')) {
            cleanLine = cleanLine.substring(0, cleanLine.length - 1);
          }
          
          try {
            final jsonData = json.decode(cleanLine);
            if (jsonData['tid'] is String) {
              jsonData['tid'] = int.parse(jsonData['tid']);
            }
            parsedEvents.add(jsonData);
            totalLines++;
          } catch (e) {
            print('Failed to parse line: $cleanLine');
            continue;
          }
        }
        
        print('청크 ${i ~/ _chunkSize + 1} 처리 시간: ${stopwatch.elapsedMilliseconds - chunkTime}ms (${chunk.length} 라인)');
        await Future.delayed(Duration.zero);
      }
      
      print('전체 청크 처리 시간: ${stopwatch.elapsedMilliseconds - chunkStartTime}ms (총 $totalLines 라인)');
      
      events = parsedEvents;
      
      final processStartTime = stopwatch.elapsedMilliseconds;
      final result = await processTraceEvents();
      print('이벤트 처리 시간: ${stopwatch.elapsedMilliseconds - processStartTime}ms');
      
      print('총 소요 시간: ${stopwatch.elapsedMilliseconds}ms');
      return result;
    } catch (error) {
      print('에러 발생 시간: ${stopwatch.elapsedMilliseconds}ms');
      throw Exception('파일 파싱 중 오류 발생: $error');
    }
  }
  
  // 별도 isolate에서 실행될 파싱 함수
  static List<dynamic> _parseChunk(List<String> lines) {
    return lines.where((line) {
      final trimmed = line.trim();
      return trimmed.isNotEmpty && trimmed != '[' && trimmed != ']';
    }).map((line) {
      var cleanLine = line.trim();
      if (cleanLine.endsWith(',')) {
        cleanLine = cleanLine.substring(0, cleanLine.length - 1);
      }
      try {
        final jsonData = json.decode(cleanLine);
        // tid를 문자열에서 정수로 변환
        if (jsonData['tid'] is String) {
          jsonData['tid'] = int.parse(jsonData['tid']);
        }
        return jsonData;
      } catch (e) {
        print('Failed to parse line: $cleanLine');
        rethrow;
      }
    }).toList();
  }

  Future<Map<String, dynamic>> processTraceEvents() async {
    final stopwatch = Stopwatch()..start();
    print('시작: 이벤트 처리');
    
    final initStartTime = stopwatch.elapsedMilliseconds;
    final processedData = _initializeProcessedData();
    print('초기화 시간: ${stopwatch.elapsedMilliseconds - initStartTime}ms');
    
    final chunksStartTime = stopwatch.elapsedMilliseconds;
    final chunks = _splitIntoChunks(events, _chunkSize);
    print('청크 분할 시간: ${stopwatch.elapsedMilliseconds - chunksStartTime}ms');
    
    final parallelStartTime = stopwatch.elapsedMilliseconds;
    final futures = chunks.map((chunk) => 
      compute(_processChunkParallel, {
        'chunk': chunk,
        'startTime': processedData['startTime'],
      })
    );
    
    final results = await Future.wait(futures);
    print('병렬 처리 시간: ${stopwatch.elapsedMilliseconds - parallelStartTime}ms');
    
    final mergeStartTime = stopwatch.elapsedMilliseconds;
    final timelineEvents = <Map<String, dynamic>>[];
    final eventsByPhase = <String, int>{};
    
    for (var result in results) {
      timelineEvents.addAll(result['timelineEvents'] as List<Map<String, dynamic>>);
      _mergePhases(eventsByPhase, result['eventsByPhase'] as Map<String, int>);
    }
    
    processedData['timelineEvents'] = timelineEvents;
    processedData['eventsByPhase'] = eventsByPhase;
    
    print('결과 병합 시간: ${stopwatch.elapsedMilliseconds - mergeStartTime}ms');
    print('총 처리 시간: ${stopwatch.elapsedMilliseconds}ms');
    
    return processedData;
  }
  
  Map<String, dynamic> _initializeProcessedData() {
    double startTime = double.maxFinite;
    double endTime = 0.0;
    
    // 빠른 첫 패스로 시작/종료 시간만 계산
    for (var event in events) {
      final ts = double.tryParse(event['ts']?.toString() ?? '0') ?? 0;
      final dur = double.tryParse(event['dur']?.toString() ?? '0') ?? 0;
      
      startTime = min(startTime, ts.toDouble());
      endTime = max(endTime, ts + dur);
    }
    
    return {
      'totalDuration': (endTime - startTime) / 1000.0,
      'eventCount': events.length,
      'eventsByPhase': <String, int>{},
      'timelineEvents': <Map<String, dynamic>>[],
      'startTime': startTime,
      'endTime': endTime,
    };
  }
  
  // 병렬 처리를 위한 청크 분할
  List<List<dynamic>> _splitIntoChunks(List<dynamic> list, int size) {
    return List.generate(
      (list.length / size).ceil(),
      (i) => list.skip(i * size).take(size).toList(),
    );
  }
  
  void _mergePhases(Map<String, int> target, Map<String, int> source) {
    source.forEach((key, value) {
      target[key] = (target[key] ?? 0) + value;
    });
  }
}

// 별도 isolate에서 실행될 이벤트 처리 함수
Map<String, dynamic> _processChunkParallel(Map<String, dynamic> params) {
  final chunk = params['chunk'] as List;
  final startTime = params['startTime'] as double;
  
  final result = {
    'eventsByPhase': <String, int>{},
    'timelineEvents': <Map<String, dynamic>>[],
  };
  
  for (var event in chunk) {
    final phase = event['ph']?.toString() ?? '';
    (result['eventsByPhase'] as Map<String, int>)[phase] = 
        ((result['eventsByPhase'] as Map<String, int>)[phase] ?? 0) + 1;
    
    if (phase == 'X') {
      final ts = double.tryParse(event['ts']?.toString() ?? '0') ?? 0;
      final dur = double.tryParse(event['dur']?.toString() ?? '0') ?? 0;
      
      // tid를 정수로 확실하게 변환
      final tid = event['tid'] is String ? 
          int.parse(event['tid']) : (event['tid'] as int);
      
      (result['timelineEvents'] as List<Map<String, dynamic>>).add({
        'name': event['name']?.toString() ?? 'Unknown',
        'startTime': ts,
        'duration': dur,
        'category': event['cat']?.toString() ?? 'default',
        'pid': int.tryParse(event['pid']?.toString() ?? '0') ?? 0,
        'tid': tid,
        'normalizedStartTime': (ts - startTime) / 1000.0,
        'normalizedDuration': dur / 1000.0,
      });
    }
  }
  
  return result;
}

class TraceViewer extends StatefulWidget {
  const TraceViewer({super.key});

  @override
  State<TraceViewer> createState() => _TraceViewerState();
}

class _TraceViewerState extends State<TraceViewer> {
  final _analyzer = TraceAnalyzer();
  Map<String, dynamic>? _analysisResults;
  String? _errorMessage;
  bool _isLoading = false;
  bool _showPanel = false;
  late DropzoneViewController _dropzoneController;
  bool _isDragging = false;

  Future<void> _processFile(String content) async {
    try {
      // 기존 데이터 초기화
      setState(() {
        _analysisResults = null;
        _showPanel = false;
      });

      final results = await _analyzer.parseTraceFile(content);
      
      setState(() {
        _analysisResults = results;
        _showPanel = true;
        _isDragging = false;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '파일 처리 중 오류가 발생했습니다: $e';
        _analysisResults = null;
        _isDragging = false;
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleDroppedFile(dynamic event) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final name = await _dropzoneController.getFilename(event);
      if (!name.toLowerCase().endsWith('.json')) {
        throw Exception('JSON 파일만 업로드할 수 있습니다.');
      }
      final bytes = await _dropzoneController.getFileData(event);
      final content = utf8.decode(bytes);
      await _processFile(content);
    } catch (e) {
      setState(() {
        _errorMessage = '파일 처리 중 오류가 발생했습니다: $e';
        _analysisResults = null;
        _isDragging = false;
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleFileUpload() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty && result.files.first.bytes != null) {
        final content = utf8.decode(result.files.first.bytes!);
        await _processFile(content);
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() {
        _errorMessage = '파일 처리 중 오류가 발생했습니다: $e';
        _analysisResults = null;
      });
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (_analysisResults != null) 
            _buildTimeline()
          else
            _buildDropzone(),
          if (_errorMessage != null) 
            _buildErrorMessage(),
          if (_isLoading)
            const LinearProgressIndicator(),
        ],
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  Widget _buildDropzone() {
    return Stack(
      children: [
        DropzoneView(
          onCreated: (controller) => _dropzoneController = controller,
          onDropFile: _handleDroppedFile,
          onHover: () => setState(() => _isDragging = true),
          onLeave: () => setState(() => _isDragging = false),
        ),
        Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border.all(
                color: _isDragging ? Colors.blue : Colors.grey,
                width: 2,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(12),
              color: _isDragging 
                  ? Colors.white.withOpacity(0.9)
                  : Colors.grey.withOpacity(0.1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.upload_file,
                  size: 48,
                  color: _isDragging ? Colors.blue : Colors.grey,
                ),
                const SizedBox(height: 16),
                Text(
                  _isDragging
                      ? '새 트레이스 파일을 여기에 드롭하세요'
                      : '트레이스 파일을 여기에 드래그하거나\n버튼을 클릭하여 업로드하세요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _isDragging ? Colors.blue : Colors.grey,
                    fontSize: 16,
                    fontWeight: _isDragging ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.3),
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    return FloatingActionButton(
      onPressed: _isLoading ? null : _handleFileUpload,
      child: _isLoading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.upload_file),
    );
  }

  Widget _buildErrorMessage() {
    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        color: Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _errorMessage = null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeline() {
    return Stack(
      children: [
        // TimelineChart를 먼저 렌더링
        SizedBox(
          width: double.infinity,
          height: MediaQuery.of(context).size.height,
          child: TimelineChart(
            key: ValueKey(_analysisResults.hashCode),
            timelineEvents: List<Map<String, dynamic>>.from(
              _analysisResults!['timelineEvents'],
            ),
            totalDuration: _analysisResults!['totalDuration'],
          ),
        ),
        // DropzoneView를 투명하게 만들고 마우스 이벤트를 통과시킴
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_isDragging,
            child: DropzoneView(
              onCreated: (controller) => _dropzoneController = controller,
              onDropFile: _handleDroppedFile,
              onHover: () => setState(() => _isDragging = true),
              onLeave: () => setState(() => _isDragging = false),
            ),
          ),
        ),
        // 드래그 중일 때 오버레이 표시
        if (_isDragging)
          Container(
            color: Colors.blue.withOpacity(0.1),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.blue,
                    width: 2,
                    style: BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white.withOpacity(0.9),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.upload_file,
                      size: 48,
                      color: Colors.blue,
                    ),
                    SizedBox(height: 16),
                    Text(
                      '새 트레이스 파일을 여기에 드롭하세요',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
} 