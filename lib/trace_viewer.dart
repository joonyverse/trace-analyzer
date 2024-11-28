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
      final jsonStartTime = stopwatch.elapsedMilliseconds;
      List<dynamic> parsedEvents;
      
      // 디버그 로그 추가
      print('파일 시작 부분: ${fileContent.substring(0, min(100, fileContent.length))}');
      print('파일 끝 부분: ${fileContent.substring(max(0, fileContent.length - 100))}');
      
      try {
        // fileContent가 '[' 로 시작하지 않으면 추가
        if (!fileContent.trimLeft().startsWith('[')) {
          fileContent = '[$fileContent';
          print('[ 추가됨');
        }
        
        // 마지막 콤마 제거
        fileContent = fileContent.trimRight();
        if (fileContent.endsWith(',')) {
          fileContent = fileContent.substring(0, fileContent.length - 1);
          print('마지막 콤마 제거됨');
        }
        
        // 마지막에 ']' 추가
        if (!fileContent.endsWith(']')) {
          fileContent = '$fileContent]';
          print('] 추가됨');
        }
        
        // 디버그용 로그
        print('파싱 시도할 데이터 시작: ${fileContent.substring(0, min(100, fileContent.length))}');
        print('파싱 시도할 데이터 끝: ${fileContent.substring(max(0, fileContent.length - 100))}');
        
        parsedEvents = json.decode(fileContent) as List<dynamic>;
        
        // tid 문자열을 정수로 변환
        for (var event in parsedEvents) {
          if (event['tid'] is String) {
            event['tid'] = int.parse(event['tid']);
          }
        }
      } catch (e, stackTrace) {
        print('JSON 파싱 실패 상세: $e');
        print('스택 트레이스: $stackTrace');
        throw Exception('JSON 파싱 실패: 올바른 형식의 트레이스 파일이 아닙니다.');
      }
      
      print('JSON 파싱 시간: ${stopwatch.elapsedMilliseconds - jsonStartTime}ms');
      
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
    
    
    // 결과를 저장할 Map 초기화
    final results = {
      'eventsByPhase': <String, int>{},
      'timelineEvents': <Map<String, dynamic>>[],
    };
    
    final eventsByPhase = results['eventsByPhase'] as Map<String, int>;
    final timelineEvents = results['timelineEvents'] as List<Map<String, dynamic>>;
    final startTime = processedData['startTime'] as double;

    for (var event in events) {
      final phase = event['ph'].toString();
      eventsByPhase[phase] = (eventsByPhase[phase] ?? 0) + 1;
        
      if (phase == 'X') {
        final ts = double.tryParse(event['ts']?.toString() ?? '0') ?? 0;
        final dur = double.tryParse(event['dur']?.toString() ?? '0') ?? 0;
        final tid = event['tid'] is String ? int.parse(event['tid']) : (event['tid'] as int? ?? 0);
          
        timelineEvents.add({
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
    

    // 결과를 processedData에 복사
    processedData['timelineEvents'] = results['timelineEvents'];
    processedData['eventsByPhase'] = results['eventsByPhase'];
    
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
          Positioned(
            top: 16,
            right: 16,
            child: _buildFloatingActionButton(),
          ),
        ],
      ),
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
    return FloatingActionButton.small(
      onPressed: _isLoading ? null : _handleFileUpload,
      child: _isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.upload_file, size: 20),
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