import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'timeline_chart.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';

class TraceAnalyzer {
  List<dynamic> events = [];

  Future<Map<String, dynamic>> parseTraceFile(String fileContent) async {
    try {
      final data = json.decode(fileContent);
      if (data['traceEvents'] != null) {
        events = data['traceEvents'];
        return processTraceEvents();
      }
      throw Exception('올바른 Trace Event Format이 아닙니다.');
    } catch (error) {
      throw Exception('파일 파싱 중 오류 발생: $error');
    }
  }

  Map<String, dynamic> processTraceEvents() {
    Map<String, dynamic> processedData = {
      'totalDuration': 0.0,
      'eventCount': events.length,
      'eventsByPhase': <String, int>{},
      'timelineEvents': <Map<String, dynamic>>[],
      'startTime': double.maxFinite,
      'endTime': 0.0
    };

    // Begin-End 페어를 찾기 위한 맵
    Map<String, Map<String, dynamic>> openEvents = {};

    // print('Processing ${events.length} events');

    // 시작 시과 종료 시간 찾기
    for (var event in events) {
      final num ts = (event['ts'] as num?) ?? 0;
      final num dur = (event['dur'] as num?) ?? 0;
      
      if (ts < processedData['startTime']) {
        processedData['startTime'] = ts.toDouble();
      }
      // X 이벤트는 dur를 포함하므로 종료 시간 계산에 포함
      if (ts + dur > processedData['endTime']) {
        processedData['endTime'] = (ts + dur).toDouble();
      }
    }

    // 이벤트 처리
    for (var event in events) {
      final String phase = (event['ph'] as String?) ?? '';
      final eventsByPhase = processedData['eventsByPhase'] as Map<String, int>;
      eventsByPhase[phase] = (eventsByPhase[phase] ?? 0) + 1;

      final num ts = (event['ts'] as num?) ?? 0;
      final String name = (event['name'] as String?) ?? 'Unknown';
      final String category = (event['cat'] as String?) ?? 'default';
      final int pid = (event['pid'] as int?) ?? 0;
      final int tid = (event['tid'] as int?) ?? 0;

      if (phase == 'X') {
        // Duration 이벤트 처리
        final num dur = (event['dur'] as num?) ?? 0;
        final timelineEvent = {
          'name': name,
          'startTime': ts,
          'duration': dur,
          'category': category,
          'pid': pid,
          'tid': tid,
          'normalizedStartTime': 
              (ts - processedData['startTime']) / 1000.0,
          'normalizedDuration': dur / 1000.0
        };

        // print('Timeline Event (X):');
        // print('  Name: $name');
        // print('  Start Time: ${timelineEvent['normalizedStartTime']}ms');
        // print('  Duration: ${timelineEvent['normalizedDuration']}ms');

        (processedData['timelineEvents'] as List<Map<String, dynamic>>)
            .add(timelineEvent);
      } else if (phase == 'B') {
        // Begin 이벤트 저장
        final key = '$name-$pid-$tid';
        openEvents[key] = {
          'name': name,
          'startTime': ts,
          'category': category,
          'pid': pid,
          'tid': tid,
        };
      } else if (phase == 'E') {
        // End 이벤트 매칭
        final key = '$name-$pid-$tid';
        final beginEvent = openEvents[key];
        if (beginEvent != null) {
          final startTime = beginEvent['startTime'] as num;
          final duration = ts - startTime;

          final timelineEvent = {
            'name': name,
            'startTime': startTime,
            'duration': duration,
            'category': category,
            'pid': pid,
            'tid': tid,
            'normalizedStartTime': 
                (startTime - processedData['startTime']) / 1000.0,
            'normalizedDuration': duration / 1000.0
          };

          // print('Timeline Event (B-E):');
          // print('  Name: $name');
          // print('  Start Time: ${timelineEvent['normalizedStartTime']}ms');
          // print('  Duration: ${timelineEvent['normalizedDuration']}ms');

          (processedData['timelineEvents'] as List<Map<String, dynamic>>)
              .add(timelineEvent);
          openEvents.remove(key);
        }
      }
    }

    final double startTime = processedData['startTime'] as double;
    final double endTime = processedData['endTime'] as double;
    processedData['totalDuration'] = (endTime - startTime) / 1000.0;
    
    // print('\nFinal Results:');
    // print('Total Duration: ${processedData['totalDuration']}ms');
    // print('Events Count: ${(processedData['timelineEvents'] as List).length}');
    // print('Start Time: ${processedData['startTime']}');
    // print('End Time: ${processedData['endTime']}');

    return processedData;
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