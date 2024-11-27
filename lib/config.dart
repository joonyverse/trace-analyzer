class TraceViewerConfig {
  // 파일 파싱 관련 설정
  static const int chunkSize = 50000;  // 청크당 처리할 라인 수
  
  // 타임라인 차트 관련 설정
  static const double initialZoomLevel = 1000.0;  // 초기 줌 레벨
  static const double zoomFactor = 1.3;  // 줌 인/아웃 시 배율
  static const double scrollAmount = 50.0;  // 스크롤 단위
  static const double dragThreshold = 5.0;  // 드래그 인식 임계값
  
  // 렌더링 최적화 관련 설정
  static const int maxVisibleEvents = 100000;  // 최대 표시 이벤트 수 증가
  static const double eventMinWidth = 0;  // 이벤트 최소 너비를 더 작게 조정
  
  // UI 관련 설정
  static const double threadLabelWidth = 50.0;  // 스레드 라벨 너비
  static const double rulerHeight = 20.0;  // 시간 눈금자 높이
  static const double trackHeight = 16.0;  // 트랙 높이
  
  // 색상 관련 설정
  static const double selectionOverlayOpacity = 0.7;  // 선택 영역 오버레이 투명도
  static const double guidelineOpacity = 0.5;  // 가이드라인 투명도
  
  // 텍스트 관련 설정
  static const double fontSize = 10.0;  // 기본 폰트 크기
  static const double timelineFontSize = 10.0;  // 타임라인 폰트 크기
  
  // 줌 관련 설정
  static const double minZoomLevel = 1.0;    // 최소 줌 레벨
  static const double maxZoomLevel = 10000.0; // 최대 줌 레벨
  
  // 이벤트 렌더링 관련 설정
  static const double eventLabelMinWidth = 40.0;  // 이벤트 라벨 표시를 위한 최소 너비
  static const double eventCornerRadius = 1.0;    // 이벤트 모서리 반경
} 