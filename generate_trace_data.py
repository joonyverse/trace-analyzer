import json
import os
import random
from datetime import datetime

def generate_random_trace_data(event_count=500000):
    # 두 단어로 된 이벤트 이름 정의
    first_words = [
        "Network", "Database", "Memory", "CPU", "Disk",
        "Audio", "Video", "Graphics", "Input", "System"
    ]
    second_words = [
        "Process", "Request", "Operation", "Task", "Handler",
        "Stream", "Buffer", "Queue", "Event", "Worker"
    ]
    
    # 첫 단어별 색상 매핑
    color_map = {
        "Network": "#ff7f7f",  # 빨간색 계열
        "Database": "#7f7fff", # 파란색 계열
        "Memory": "#7fff7f",   # 초록색 계열
        "CPU": "#ff7fff",      # 분홍색 계열
        "Disk": "#ffff7f",     # 노란색 계열
        "Audio": "#7fffff",    # 청록색 계열
        "Video": "#ff7f00",    # 주황색 계열
        "Graphics": "#007fff", # 하늘색 계열
        "Input": "#7f00ff",    # 보라색 계열
        "System": "#7f7f7f"    # 회색 계열
    }
    
    events = []
    thread_ids = list(range(1, 31))
    categories = ["rendering", "computing", "io", "network", "painting", "gc"]
    
    thread_events = {tid: [] for tid in thread_ids}
    
    for _ in range(event_count):
        first_word = random.choice(first_words)
        second_word = random.choice(second_words)
        name = f"{first_word} {second_word}"
        
        tid = random.choice(thread_ids)
        duration = random.randint(10, 100)
        
        event = {
            "name": str(name),
            "cat": str(random.choice(categories)),
            "ph": "X",
            "pid": str(1),
            "tid": str(tid),
            "dur": str(duration),
            "ts": "0",
            "cname": str(color_map[first_word])
        }
        
        thread_events[tid].append(event)
    
    # 시간 설정 부분 수정
    for tid, events in thread_events.items():
        current_time = 0
        for event in events:
            # 이벤트 시작 시간을 무작위로 설정하여 중첩 허용
            event["ts"] = str(random.randint(current_time, current_time + 50))
            current_time += int(event["dur"]) + random.randint(1, 20)
    
    # 모든 이벤트를 하나의 리스트로 합침
    all_events = [event for events in thread_events.values() for event in events]
    
    return all_events

# JSON 형식으로 출력
trace_data = generate_random_trace_data()

with open('test-data.json', 'w') as f:
    f.write('[')  # 배열 시작
    for event in trace_data:
        json_str = json.dumps(event, separators=(',', ':'))
        f.write(json_str + ',\n')  # 모든 이벤트 뒤에 쉼표 추가
    # 닫는 대괄호 없이 저장

print(f"Generated trace data file size: {os.path.getsize('test-data.json') / (1024 * 1024):.2f}MB")

# 생성된 데이터 검증
threads = {}
for event in trace_data:
    tid = event["tid"]
    if tid not in threads:
        threads[tid] = []
    threads[tid].append(event)

# 각 스레드별로 이벤트 오버랩 체크
for tid, thread_events in threads.items():
    thread_events.sort(key=lambda x: x['ts'])
    for i in range(len(thread_events) - 1):
        current_event = thread_events[i]
        next_event = thread_events[i + 1]
        current_end = current_event['ts'] + current_event['dur']
        next_start = next_event['ts']