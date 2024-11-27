import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math';  // min, max 함수를 위해 추가
import 'config.dart';

class TimelineChart extends StatefulWidget {
  final List<Map<String, dynamic>> timelineEvents;
  final double totalDuration;

  const TimelineChart({
    super.key,
    required this.timelineEvents,
    required this.totalDuration,
  });

  @override
  State<TimelineChart> createState() => _TimelineChartState();
}

class _TimelineChartState extends State<TimelineChart> {
  final _focusNode = FocusNode();
  double _zoomLevel = TraceViewerConfig.initialZoomLevel;
  double _scrollOffset = 0.0;
  static const double _zoomFactor = TraceViewerConfig.zoomFactor;
  static const double _scrollAmount = TraceViewerConfig.scrollAmount;
  
  // 뷰포트 상태
  double _viewportStart = 0.0;
  double _viewportDuration = 0.0;
  
  // 캐시를 위한 변수들
  late Map<int, List<Map<String, dynamic>>> _threadEvents;
  List<int> _sortedThreadIds = [];
  
  // 렌더링 최적화를 위한 변수들
  final int _maxVisibleEvents = TraceViewerConfig.maxVisibleEvents;
  bool _isRendering = false;
  
  Offset? _lastMousePosition;  // 마우스 위치 용 변수 추가
  
  // 스레드별 트랙 수를 저장하는 맵 추가
  late Map<int, int> _threadTrackCount;
  
  // 드래그 선택을 위한 변수들 추가
  Offset? _dragStart;
  Offset? _dragEnd;
  
  // 드래그 거리 임계값 추가
  static const double _dragThreshold = TraceViewerConfig.dragThreshold;
  Offset? _dragStartPosition;  // 드래그 시작 위치 저장용

  // 마우스 가이드라인 관련 변수들
  Offset? _guidelinePosition;  // 마우스 가이드라인을 위한 별도 변수
  bool _isDragging = false;  // 드래그 상태 추적을 위한 변수 추가

  @override
  void initState() {
    super.initState();
    _viewportDuration = widget.totalDuration;
    _initializeEventCache();
    
    // 포커스 노드 리스너 추가
    _focusNode.addListener(_handleFocusChange);
    
    // 다음 프레임에서 포커스 요청
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      // 포커스를 잃었을 때 자동으로 다시 포커스 요청
      _focusNode.requestFocus();
    }
  }

  void _initializeEventCache() {
    // 백그라운드 isolate에서 데이터 처리
    _processEventsInBackground();
  }

  Future<void> _processEventsInBackground() async {
    final stopwatch = Stopwatch()..start();
    print('시작: 이벤트 백그라운드 처리');
    
    _threadEvents = {};
    _threadTrackCount = {};
    
    // 스레드별로 이벤트 그룹화
    final groupStartTime = stopwatch.elapsedMilliseconds;
    for (final event in widget.timelineEvents) {
      final tid = event['tid'] as int;
      _threadEvents.putIfAbsent(tid, () => []).add(event);
    }
    print('스레드별 그룹화 시간: ${stopwatch.elapsedMilliseconds - groupStartTime}ms');
    
    _sortedThreadIds = _threadEvents.keys.toList()..sort();
    
    // 각 스레드의 이벤트를 시간순으로 정렬하고 트랙 할당
    for (var tid in _sortedThreadIds) {
      final sortTime = stopwatch.elapsedMilliseconds;
      var events = _threadEvents[tid]!;
      events.sort((a, b) => (a['normalizedStartTime'] as double)
          .compareTo(b['normalizedStartTime'] as double));
      print('스레드 $tid 이벤트 정렬 시간: ${stopwatch.elapsedMilliseconds - sortTime}ms (${events.length} 이벤트)');
      
      final allocTime = stopwatch.elapsedMilliseconds;
      // 최적화된 트랙 할당 알고리즘
      final tracks = _assignTracksOptimized(events);
      print('스레드 $tid 트랙 할당 시간: ${stopwatch.elapsedMilliseconds - allocTime}ms (${tracks.length} 트랙)');
      
      // 트랙 수 저장
      _threadTrackCount[tid] = tracks.length;
      
      // 이벤트에 트랙 인덱스 추가
      for (var i = 0; i < tracks.length; i++) {
        for (var event in tracks[i]) {
          event['trackIndex'] = i;
        }
      }
    }

    if (mounted) setState(() {});
  }

  List<List<Map<String, dynamic>>> _assignTracksOptimized(List<Map<String, dynamic>> events) {
    if (events.isEmpty) return [];
    
    // 각 트랙의 마지막 이벤트의 종료 시간을 저장
    final trackEndTimes = <double>[];
    final tracks = <List<Map<String, dynamic>>>[];
    
    for (var event in events) {
      final startTime = event['normalizedStartTime'] as double;
      final duration = event['normalizedDuration'] as double;
      final endTime = startTime + duration;
      
      // 기존 트랙 중에서 이벤트를 배치할 수 있는 트랙 찾기
      bool placed = false;
      for (var i = 0; i < trackEndTimes.length; i++) {
        if (startTime >= trackEndTimes[i]) {
          // 트랙에 이벤트 추가
          tracks[i].add(event);
          trackEndTimes[i] = endTime;
          placed = true;
          break;
        }
      }
      
      // 기존 트랙에 배치할 수 없으면 새 트랙 생성
      if (!placed) {
        tracks.add([event]);
        trackEndTimes.add(endTime);
      }
    }
    
    return tracks;
  }

  bool canAddToTrack(List<Map<String, dynamic>> track, Map<String, dynamic> newEvent) {
    if (track.isEmpty) return true;
    
    final newStart = newEvent['normalizedStartTime'] as double;
    final newEnd = newStart + (newEvent['normalizedDuration'] as double);
    
    for (var event in track) {
      final start = event['normalizedStartTime'] as double;
      final end = start + (event['normalizedDuration'] as double);
      
      if (!(newEnd <= start || newStart >= end)) {
        return false;
      }
    }
    return true;
  }

  List<Map<String, dynamic>> _getVisibleEvents() {
    if (_isRendering) return [];
    _isRendering = true;

    final viewportEnd = _viewportStart + _viewportDuration;
    final visibleEventsByThread = <int, List<Map<String, dynamic>>>{};
    
    try {
      // 1. 각 스레드별로 뷰포트 내 이벤트 수집 및 필터링
      for (var tid in _sortedThreadIds) {
        final events = _threadEvents[tid]!;
        int start = _binarySearch(events, _viewportStart);
        
        final threadEvents = <Map<String, dynamic>>[];
        for (var i = start; i < events.length; i++) {
          final event = events[i];
          final startTime = event['normalizedStartTime'] as double;
          if (startTime > viewportEnd) break;
          
          final duration = event['normalizedDuration'] as double;
          if (duration > 0) {  // duration이 0인 이벤트는 제외
            threadEvents.add(event);
          }
        }
        
        if (threadEvents.isNotEmpty) {
          // 2. 각 스레드의 이벤트를 duration 기준으로 정렬
          threadEvents.sort((a, b) => (b['normalizedDuration'] as double)
              .compareTo(a['normalizedDuration'] as double));
          visibleEventsByThread[tid] = threadEvents;
        }
      }

      // 3. 스레드별로 가장 긴 이벤트부터 선택
      final visibleEvents = <Map<String, dynamic>>[];
      int totalSelected = 0;
      bool hasMoreEvents = true;
      
      while (hasMoreEvents && totalSelected < _maxVisibleEvents) {
        hasMoreEvents = false;
        
        for (var tid in _sortedThreadIds) {
          final threadEvents = visibleEventsByThread[tid];
          if (threadEvents == null || threadEvents.isEmpty) continue;
          
          final event = threadEvents.removeAt(0);  // 가장 긴 이벤트 선택
          visibleEvents.add(event);
          totalSelected++;
          
          if (threadEvents.isNotEmpty) {
            hasMoreEvents = true;
          }
          
          if (totalSelected >= _maxVisibleEvents) break;
        }
      }

      // 4. 최종 정렬: 스레드 ID -> 시작 시간 순
      visibleEvents.sort((a, b) {
        final tidCompare = (a['tid'] as int).compareTo(b['tid'] as int);
        if (tidCompare != 0) return tidCompare;
        return (a['normalizedStartTime'] as double)
            .compareTo(b['normalizedStartTime'] as double);
      });

      return visibleEvents;
    } finally {
      _isRendering = false;
    }
  }

  int _binarySearch(List<Map<String, dynamic>> events, double targetTime) {
    int left = 0;
    int right = events.length - 1;
    
    while (left <= right) {
      int mid = (left + right) ~/ 2;
      double startTime = events[mid]['normalizedStartTime'];
      
      if (startTime < targetTime) {
        left = mid + 1;
      } else {
        right = mid - 1;
      }
    }
    
    return right + 1;
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      autofocus: true,
      child: Focus(
        focusNode: _focusNode,
        onKey: (node, event) {
          if (event is RawKeyDownEvent) {
            _handleKeyEvent(event);
          }
          return KeyEventResult.handled;
        },
        child: MouseRegion(
          onHover: (event) {
            setState(() {
              _lastMousePosition = event.localPosition;
            });
          },
          onExit: (event) {
            setState(() {
              _lastMousePosition = null;
            });
          },
          child: GestureDetector(
            onTapDown: (_) => _focusNode.requestFocus(),
            onPanStart: (details) {
              _focusNode.requestFocus();
              setState(() {
                _dragStartPosition = details.localPosition;
                _dragStart = details.localPosition;
                _dragEnd = details.localPosition;
                _isDragging = true;
              });
            },
            onPanUpdate: (details) {
              if (_dragStartPosition != null) {
                final dragDistance = (details.localPosition - _dragStartPosition!).distance;
                if (dragDistance > _dragThreshold) {
                  setState(() {
                    _dragEnd = details.localPosition;
                  });
                }
              }
            },
            onPanEnd: (details) {
              if (_dragStartPosition != null) {
                final dragDistance = (_dragEnd! - _dragStartPosition!).distance;
                if (dragDistance <= _dragThreshold) {
                  setState(() {
                    _dragStart = null;
                    _dragEnd = null;
                  });
                }
              }
              setState(() {
                _dragStartPosition = null;
                _isDragging = false;
              });
            },
            onPanCancel: () {
              setState(() {
                _dragStart = null;
                _dragEnd = null;
                _dragStartPosition = null;
                _isDragging = false;
              });
            },
            behavior: HitTestBehavior.translucent,
            child: LayoutBuilder(
              builder: (context, constraints) {
                _viewportDuration = widget.totalDuration / _zoomLevel;
                _viewportStart = _scrollOffset.clamp(
                  0.0,
                  widget.totalDuration - _viewportDuration,
                );

                double totalHeight = 0;
                for (var tid in _sortedThreadIds) {
                  final trackCount = _threadTrackCount[tid] ?? 1;
                  totalHeight += trackCount * TraceViewerConfig.trackHeight;
                }

                return Stack(
                  children: [
                    // 고정된 눈금자
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: TraceViewerConfig.rulerHeight,
                      child: CustomPaint(
                        painter: TimeRulerPainter(
                          viewportStart: _viewportStart,
                          viewportDuration: _viewportDuration,
                          threadLabelWidth: TraceViewerConfig.threadLabelWidth,
                        ),
                      ),
                    ),
                    // 스크롤 가능한 타임라인 컨텐츠
                    Padding(
                      padding: EdgeInsets.only(top: TraceViewerConfig.rulerHeight),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SizedBox(
                          width: constraints.maxWidth,
                          height: totalHeight,
                          child: CustomPaint(
                            size: Size(constraints.maxWidth, totalHeight),
                            painter: TimelinePainter(
                              events: _getVisibleEvents(),
                              threadIds: _sortedThreadIds,
                              viewportStart: _viewportStart,
                              viewportDuration: _viewportDuration,
                              zoomLevel: _zoomLevel,
                              totalDuration: widget.totalDuration,
                              threadTrackCount: _threadTrackCount,
                              dragStart: _dragStart,
                              dragEnd: _dragEnd,
                              threadLabelWidth: TraceViewerConfig.threadLabelWidth,
                              lastMousePosition: _lastMousePosition,
                              guidelinePosition: _guidelinePosition,
                              isDragging: _isDragging,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _handleKeyEvent(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      setState(() {
        final oldZoom = _zoomLevel;
        final threadLabelWidth = TraceViewerConfig.threadLabelWidth;

        switch (event.logicalKey) {
          case LogicalKeyboardKey.keyW:
          case LogicalKeyboardKey.keyS:
            if (_lastMousePosition != null) {
              final mouseX = _lastMousePosition!.dx - threadLabelWidth;
              final availableWidth = context.size!.width - threadLabelWidth;
              final mouseTimeOffset = (mouseX / availableWidth) * _viewportDuration;
              final mouseAbsoluteTime = _viewportStart + mouseTimeOffset;

              if (event.logicalKey == LogicalKeyboardKey.keyW) {
                _zoomLevel = (_zoomLevel * _zoomFactor)
                    .clamp(TraceViewerConfig.minZoomLevel, TraceViewerConfig.maxZoomLevel);
              } else {
                _zoomLevel = (_zoomLevel / _zoomFactor)
                    .clamp(TraceViewerConfig.minZoomLevel, TraceViewerConfig.maxZoomLevel);
              }

              _viewportDuration = widget.totalDuration / _zoomLevel;
              
              final newMouseTimeOffset = mouseTimeOffset * (oldZoom / _zoomLevel);
              _scrollOffset = (mouseAbsoluteTime - newMouseTimeOffset)
                  .clamp(0.0, widget.totalDuration - _viewportDuration);
            } else {
              final centerTime = _viewportStart + (_viewportDuration / 2);
              
              if (event.logicalKey == LogicalKeyboardKey.keyW) {
                _zoomLevel = (_zoomLevel * _zoomFactor)
                    .clamp(TraceViewerConfig.minZoomLevel, TraceViewerConfig.maxZoomLevel);
              } else {
                _zoomLevel = (_zoomLevel / _zoomFactor)
                    .clamp(TraceViewerConfig.minZoomLevel, TraceViewerConfig.maxZoomLevel);
              }

              _viewportDuration = widget.totalDuration / _zoomLevel;
              _scrollOffset = (centerTime - _viewportDuration / 2)
                  .clamp(0.0, widget.totalDuration - _viewportDuration);
            }
            break;

          case LogicalKeyboardKey.keyA:
            _scrollOffset = (_scrollOffset - _scrollAmount / _zoomLevel)
                .clamp(0.0, widget.totalDuration - _viewportDuration);
            break;
          case LogicalKeyboardKey.keyD:
            _scrollOffset = (_scrollOffset + _scrollAmount / _zoomLevel)
                .clamp(0.0, widget.totalDuration - _viewportDuration);
            break;
        }

        _viewportStart = _scrollOffset;
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  // ... (나머지 메서드들은 동일)
}

class TimelinePainter extends CustomPainter {
  final List<Map<String, dynamic>> events;
  final List<int> threadIds;
  final double viewportStart;
  final double viewportDuration;
  final double zoomLevel;
  final double totalDuration;
  final Map<int, int> threadTrackCount;
  final Offset? dragStart;
  final Offset? dragEnd;
  final double threadLabelWidth;
  final Offset? lastMousePosition;
  final Offset? guidelinePosition;
  final bool isDragging;

  TimelinePainter({
    required this.events,
    required this.threadIds,
    required this.viewportStart,
    required this.viewportDuration,
    required this.zoomLevel,
    required this.totalDuration,
    required this.threadTrackCount,
    this.dragStart,
    this.dragEnd,
    required this.threadLabelWidth,
    this.lastMousePosition,
    this.guidelinePosition,
    required this.isDragging,
  });

  String _formatTime(double timeMs) {
    if (timeMs >= 1000000) {
      return '${(timeMs/1000000).toStringAsFixed(2)}ks';
    } else if (timeMs >= 1000) {
      return '${(timeMs/1000).toStringAsFixed(2)}s';
    } else if (timeMs >= 1) {
      return '${timeMs.toStringAsFixed(2)}ms';
    } else if (timeMs >= 0.001) {
      return '${(timeMs * 1000).toStringAsFixed(2)}μs';
    } else {
      return '${(timeMs * 1000000).toStringAsFixed(2)}ns';
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final availableWidth = size.width - threadLabelWidth;
    final trackHeight = TraceViewerConfig.trackHeight;
    var currentY = 0.0;

    // 배경 그리기
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    // 트랙과 이벤트 그리기
    for (var tid in threadIds) {
      final trackCount = threadTrackCount[tid] ?? 1;
      
      // 스레드 레이블 배경
      canvas.drawRect(
        Rect.fromLTWH(0, currentY, threadLabelWidth, trackHeight * trackCount),
        Paint()..color = Colors.grey.shade100,
      );
      
      // 스레드 레이블 그리기
      _drawThreadLabel(canvas, tid, currentY, threadLabelWidth, trackHeight * trackCount);
      
      // 트랙 배경 그리기
      for (var i = 0; i < trackCount; i++) {
        final isEven = i % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(threadLabelWidth, currentY + (i * trackHeight), 
              size.width - threadLabelWidth, trackHeight),
          Paint()..color = isEven ? Colors.grey.shade50 : Colors.white,
        );
      }
      
      // 이벤트 그리기
      for (final event in events.where((e) => e['tid'] == tid)) {
        final trackIndex = event['trackIndex'] as int;
        final normalizedStart = (event['normalizedStartTime'] - viewportStart) / viewportDuration;
        final normalizedWidth = event['normalizedDuration'] / viewportDuration;
        
        final left = normalizedStart * availableWidth + threadLabelWidth;
        final top = currentY + (trackIndex * trackHeight);
        final width = normalizedWidth * availableWidth;
        
        final eventHeight = trackHeight;  // 이벤트 높이도 비례해서 감소
        
        final rect = Rect.fromLTWH(
          left,
          top,
          width.clamp(1.0, double.infinity),
          eventHeight,
        );

        paint.color = _getEventColor(event['category'] as String);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(1)),  // 반경도 감소
          paint,
        );

        // 이벤트 이름 그리기 (너비가 충분할 때만)
        if (width > 40) {
          final name = event['name'] as String;
          final textStyle = ui.TextStyle(
            color: Colors.black.withOpacity(0.8),
            fontSize: 11,  // 9에 11로 증가
            fontWeight: FontWeight.w500,
          );
          
          final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
            textAlign: TextAlign.left,
            fontSize: 11,  // 8에서 11로 증가
            ellipsis: '...',
            height: 1.1,
          ))
            ..pushStyle(textStyle)
            ..addText(name);

          final paragraph = paragraphBuilder.build()
            ..layout(ui.ParagraphConstraints(width: width - 4));  // 패딩도 감소

          final textY = top + (trackHeight - paragraph.height) / 2;
          canvas.drawParagraph(
            paragraph,
            Offset(left + 2, textY),  // 패딩 감소
          );
        }
      }
      
      currentY += trackHeight * trackCount;
    }

    // 드래그 선택 영역 그리기 (맨 마지막에 그려서 항상 위에 보이도록)
    if (dragStart != null && dragEnd != null && 
        (dragStart!.dx != dragEnd!.dx || dragStart!.dy != dragEnd!.dy)) {
      // 드래그 좌표를 스크롤 위치를 고려하여 조정
      final adjustedDragStartY = dragStart!.dy - TraceViewerConfig.rulerHeight;
      final adjustedDragEndY = dragEnd!.dy - TraceViewerConfig.rulerHeight;
      
      final left = dragStart!.dx.clamp(threadLabelWidth, size.width);
      final right = dragEnd!.dx.clamp(threadLabelWidth, size.width);
      
      // 선택되지 않은 영역에 회색 음영 처리
      final leftOverlay = Rect.fromLTRB(
        threadLabelWidth,
        0,
        min(left, right),
        size.height,
      );
      final rightOverlay = Rect.fromLTRB(
        max(left, right),
        0,
        size.width,
        size.height,
      );

      // 선택되지 않은 영역 그리기
      canvas.drawRect(
        leftOverlay,
        Paint()
          ..color = Colors.grey.withOpacity(TraceViewerConfig.selectionOverlayOpacity)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        rightOverlay,
        Paint()
          ..color = Colors.grey.withOpacity(TraceViewerConfig.selectionOverlayOpacity)
          ..style = PaintingStyle.fill,
      );

      // 선택 구간의 시간 계산
      final startTime = viewportStart + 
          ((min(left, right) - threadLabelWidth) / (size.width - threadLabelWidth)) * viewportDuration;
      final endTime = viewportStart + 
          ((max(left, right) - threadLabelWidth) / (size.width - threadLabelWidth)) * viewportDuration;
      final duration = endTime - startTime;

      // 선택 구간 시간 표시
      final timeText = '${_formatTime(startTime)} - ${_formatTime(endTime)}\nDuration: ${_formatTime(duration)}';
      final textStyle = ui.TextStyle(
        color: Colors.black87,
        fontSize: 10,
        fontWeight: FontWeight.w500,
        background: Paint()..color = Colors.white.withOpacity(0.8),
      );

      final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: TextAlign.center,
        fontSize: 10,
        height: 1.2,
      ))
        ..pushStyle(textStyle)
        ..addText(timeText);

      final paragraph = paragraphBuilder.build()
        ..layout(ui.ParagraphConstraints(width: 200));

      // 시간 정보를 드래그 시작 높이에 표시 (스크롤 위치 고려)
      canvas.drawParagraph(
        paragraph,
        Offset(
          (left + right - paragraph.width) / 2,
          adjustedDragStartY,  // 조정된 Y 좌표 사용
        ),
      );

      // 세로 가이드라인 그리기
      final guidelinePaint = Paint()
        ..color = Colors.grey.withOpacity(TraceViewerConfig.guidelineOpacity)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;

      canvas.drawLine(
        Offset(left, 0),
        Offset(left, size.height),
        guidelinePaint,
      );
      canvas.drawLine(
        Offset(right, 0),
        Offset(right, size.height),
        guidelinePaint,
      );
    }

    // 마우스 가이드라인 그리기 (드래그 중이 아닐 때만)
    if (!isDragging && lastMousePosition != null && 
        lastMousePosition!.dx >= threadLabelWidth && 
        lastMousePosition!.dx <= size.width) {
      final mouseX = lastMousePosition!.dx;
      
      // 시간 계산
      final mouseTime = viewportStart + 
          ((mouseX - threadLabelWidth) / (size.width - threadLabelWidth)) * viewportDuration;
      
      // 가이드라인 그리기
      canvas.drawLine(
        Offset(mouseX, 0),
        Offset(mouseX, size.height),
        Paint()
          ..color = Colors.grey.withOpacity(TraceViewerConfig.guidelineOpacity)
          ..strokeWidth = 0.5,
      );

      // 시간 텍스트 표시
      final timeText = _formatTime(mouseTime);
      final textStyle = ui.TextStyle(
        color: Colors.black87,
        fontSize: 10,
        fontWeight: FontWeight.w500,
        background: Paint()..color = Colors.white.withOpacity(0.9),
      );

      final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: TextAlign.center,
        fontSize: 10,
      ))
        ..pushStyle(textStyle)
        ..addText(timeText);

      final paragraph = paragraphBuilder.build()
        ..layout(ui.ParagraphConstraints(width: 100));

      final textX = mouseX - paragraph.width / 2;
      final textX2 = textX.clamp(threadLabelWidth, size.width - paragraph.width);
      canvas.drawParagraph(
        paragraph,
        Offset(textX2, lastMousePosition!.dy - paragraph.height - 5),
      );
    }

    // 마우스 가이드라인 그리기 (드래그 중이 아닐 때)
    if (guidelinePosition != null && 
        guidelinePosition!.dx >= threadLabelWidth && 
        guidelinePosition!.dx <= size.width) {
      final mouseX = guidelinePosition!.dx;
      
      // 가이드라인 그리기
      canvas.drawLine(
        Offset(mouseX, 0),
        Offset(mouseX, size.height),
        Paint()
          ..color = Colors.grey.withOpacity(TraceViewerConfig.guidelineOpacity)
          ..strokeWidth = 0.5,
      );
    }
  }

  void _drawThreadLabel(Canvas canvas, int tid, double y, double width, double height) {
    final textStyle = ui.TextStyle(
      color: Colors.black87,
      fontSize: 10,
    );
    
    final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: 10,
    ))
      ..pushStyle(textStyle)
      ..addText('$tid');
    
    final paragraph = paragraphBuilder.build()
      ..layout(ui.ParagraphConstraints(width: width));
    
    canvas.drawParagraph(
      paragraph,
      Offset(0, y + (height - paragraph.height) / 2),
    );
  }

  Color _getEventColor(String category) {
    final colors = {
      'rendering': Colors.blue.shade300,
      'painting': Colors.green.shade300,
      'computing': Colors.orange.shade300,
      'network': Colors.purple.shade300,
      'io': Colors.red.shade300,
      'gc': Colors.brown.shade300,
      'default': Colors.grey.shade300,
    };
    return (colors[category] ?? colors['default']!).withOpacity(0.9);
  }

  @override
  bool shouldRepaint(TimelinePainter oldDelegate) =>
      events != oldDelegate.events ||
      viewportStart != oldDelegate.viewportStart ||
      viewportDuration != oldDelegate.viewportDuration ||
      zoomLevel != oldDelegate.zoomLevel;
}

class TimeRulerPainter extends CustomPainter {
  final double viewportStart;
  final double viewportDuration;
  final double threadLabelWidth;

  TimeRulerPainter({
    required this.viewportStart,
    required this.viewportDuration,
    required this.threadLabelWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // 눈금자 배경
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, TraceViewerConfig.rulerHeight),
      Paint()..color = Colors.grey.shade50,
    );

    // 주요 간격 (10개 구간)
    final majorIntervalWidth = (size.width - threadLabelWidth) / 10;
    final timeInterval = viewportDuration / 10;

    // 보조 간격 (각 주요 간격을 5개로 분할)
    final minorIntervalWidth = majorIntervalWidth / 5;

    // 텍스트 스타일 설정
    final textStyle = ui.TextStyle(
      color: Colors.black87,
      fontSize: TraceViewerConfig.timelineFontSize,
    );

    // 보조 눈금 그리기
    for (var i = 0; i <= 50; i++) {
      final x = i * minorIntervalWidth + threadLabelWidth;
      final isMajor = i % 5 == 0;
      
      canvas.drawLine(
        Offset(x, TraceViewerConfig.rulerHeight - (isMajor ? 6 : 3)),
        Offset(x, TraceViewerConfig.rulerHeight),
        paint,
      );

      if (isMajor) {
        final time = viewportStart + ((i / 5) * timeInterval);
        final timeText = _formatTime(time);
        
        final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
          textAlign: TextAlign.center,
          fontSize: TraceViewerConfig.timelineFontSize,
          height: 1.0,
        ))
          ..pushStyle(textStyle)
          ..addText(timeText);

        final paragraph = paragraphBuilder.build()
          ..layout(ui.ParagraphConstraints(width: majorIntervalWidth));

        canvas.drawParagraph(
          paragraph,
          Offset(x - majorIntervalWidth/2, 1),
        );
      }
    }

    // 테두리
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, TraceViewerConfig.rulerHeight),
      paint,
    );
  }

  String _formatTime(double timeMs) {
    if (timeMs >= 1000000) {
      return '${(timeMs/1000000).toStringAsFixed(2)}ks';
    } else if (timeMs >= 1000) {
      return '${(timeMs/1000).toStringAsFixed(2)}s';
    } else if (timeMs >= 1) {
      return '${timeMs.toStringAsFixed(2)}ms';
    } else if (timeMs >= 0.001) {
      return '${(timeMs * 1000).toStringAsFixed(2)}μs';
    } else {
      return '${(timeMs * 1000000).toStringAsFixed(2)}ns';
    }
  }

  @override
  bool shouldRepaint(TimeRulerPainter oldDelegate) =>
      viewportStart != oldDelegate.viewportStart ||
      viewportDuration != oldDelegate.viewportDuration;
} 