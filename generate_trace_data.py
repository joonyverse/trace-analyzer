import json
import random
from datetime import datetime

def generate_random_trace_data(event_count=10000):
    events = []
    process_ids = list(range(1, 2))  # 1개의 프로세스
    thread_ids = list(range(1, 11))  # 10개의 스레드
    categories = ['rendering', 'painting', 'computing', 'network', 'io', 'gc']
    event_names = [
        'LoadURL', 'ParseHTML', 'Layout', 'Paint', 'Composite',
        'JavaScript', 'GarbageCollection', 'NetworkRequest', 'DiskIO',
        'ImageDecode', 'VideoFrame', 'AudioProcess', 'DatabaseQuery',
        'APICall', 'WebGLRender'
    ]

    # 각 스레드별 이벤트 리스트를 따로 관리
    thread_events = {tid: [] for tid in thread_ids}
    
    # Duration (X) 이벤트 생성
    for _ in range(event_count):
        tid = random.choice(thread_ids)
        duration = random.randint(10, 100)
        
        if not thread_events[tid]:  # 해당 스레드의 첫 이벤트인 경우
            start_time = random.randint(0, 1000)
        else:
            # 마지막 이벤트의 시간만 확인하도록 단순화
            last_event = thread_events[tid][-1]
            last_end_time = last_event['ts'] + last_event['dur']
            
            # 중첩 확률을 낮춤
            if random.random() < 0.3 and len(thread_events[tid]) > 0:
                parent_event = last_event  # 마지막 이벤트만 부모로 사용
                parent_start = parent_event['ts']
                parent_end = parent_start + parent_event['dur']
                
                if duration > parent_event['dur']:
                    duration = random.randint(10, parent_event['dur'])
                
                start_time = random.randint(parent_start, parent_end - duration)
            else:
                start_time = last_end_time + random.randint(1, 5)  # 간격을 줄임
        
        event = {
            "name": random.choice(event_names),
            "cat": random.choice(categories),
            "ph": "X",
            "pid": random.choice(process_ids),
            "tid": tid,
            "ts": start_time,
            "dur": duration
        }
        
        thread_events[tid].append(event)
    
    # 모든 스레드의 이벤트를 하나의 리스트로 합치기
    events = [event for thread_list in thread_events.values() for event in thread_list]
    
    # 이벤트를 시간순으로 정렬
    events.sort(key=lambda x: x['ts'])

    return {
        "traceEvents": events,
        "metadata": {
            "generated_at": datetime.now().isoformat(),
            "event_count": len(events)
        }
    }

# 트레이스 데이터 생성 및 저장
trace_data = generate_random_trace_data()
with open('test-data.json', 'w') as f:
    json.dump(trace_data, f, indent=2)

# 파일 크기 확인
import os
file_size = os.path.getsize('test-data.json') / (1024 * 1024)  # MB로 변환
print(f"Generated trace data file size: {file_size:.2f}MB")

# 생성된 데이터 검증
threads = {}
for event in trace_data["traceEvents"]:
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
        if current_end > next_start:
            print(f"Warning: Overlap detected in thread {tid}")
            print(f"Event 1: {current_event['name']} ({current_event['ts']} -> {current_end})")
            print(f"Event 2: {next_event['name']} ({next_start} -> {next_event['ts'] + next_event['dur']})") 