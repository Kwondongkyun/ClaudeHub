# ClaudeHub Design Document

## Overview

macOS 메뉴바 앱으로, Claude Code의 모든 프로젝트/세션을 한 화면에서 관리하고 클릭 한 번으로 resume할 수 있는 도구.

**해결하는 문제**: Claude Code 세션을 이어서 작업하려면 매번 해당 디렉토리로 `cd` → `/resume` → 세션 찾기를 반복해야 하는 번거로움.

## Tech Stack

- **언어**: Swift 5.9+
- **UI**: SwiftUI (MenuBarExtra)
- **타겟**: macOS 13 Ventura+
- **의존성**: 없음 (네이티브)
- **배포**: DMG

## Architecture

```
ClaudeHub/
├── Package.swift
├── build.sh
└── Sources/
    ├── ClaudeHubApp.swift          # @main, MenuBarExtra
    ├── Models/
    │   ├── Session.swift           # 세션 데이터 모델
    │   └── Project.swift           # 프로젝트(디렉토리) 모델
    ├── Services/
    │   ├── SessionScanner.swift    # ~/.claude/projects/ 파싱
    │   ├── SessionParser.swift     # JSONL → Session 모델 변환
    │   └── TerminalLauncher.swift  # 터미널 앱 실행 + resume 명령
    └── Views/
        ├── MainView.swift          # 메인 팝오버 (사이드바 + 카드 리스트)
        ├── ProjectSidebar.swift    # 좌측 프로젝트 목록
        ├── SessionCardView.swift   # 개별 세션 카드
        ├── SearchBar.swift         # 세션 검색
        └── SettingsView.swift      # 설정 (터미널 선택 등)
```

## Data Models

### Session

```swift
struct Session: Identifiable {
    let id: String              // UUID (파일명에서 추출)
    let projectPath: String     // 원래 디렉토리 경로 (cwd)
    let title: String           // 첫 번째 사용자 메시지 (80자 제한)
    let lastModified: Date      // 파일 수정 시간
    let gitBranch: String?      // 세션 시작 시 브랜치
    let claudeVersion: String?  // 사용한 Claude 버전
    var isPinned: Bool          // 북마크 여부
}
```

### Project

```swift
struct Project: Identifiable {
    let id: String              // 폴더명
    let displayName: String     // 마지막 경로 컴포넌트 (e.g. "Claude-Code")
    let fullPath: String        // 원래 디렉토리 경로
    var sessions: [Session]
}
```

## Data Source

- 위치: `~/.claude/projects/`
- 폴더명: `-` 구분자를 `/`로 변환해서 원래 경로 복원
  - `-Users-kwondong-kyun-Desktop-Claude-Code` → `/Users/kwondong-kyun/Desktop/Claude-Code`
- 세션 파일: `<UUID>.jsonl`
  - 첫 번째 줄에서 `cwd`, `sessionId`, `gitBranch`, `version` 추출
  - 앞쪽 10줄 이내에서 첫 번째 사용자 메시지 추출 (세션 제목)
  - 파일 `modificationDate`를 마지막 활동 시간으로 사용
- 핀 상태: `UserDefaults`에 `Set<String>` (세션 ID)로 저장

## UI Layout

좌/우 분할 레이아웃 (30:70)

```
┌──────────────────────────────────────────────────────┐
│  🔍 세션 검색...                              ⚙️     │
├───────────────┬──────────────────────────────────────┤
│               │                                      │
│  Claude-Code  │  ┌──────────────────────────────┐    │
│  ● 6 세션     │  │ 📌 PortMan 만들기 프로젝트    │    │
│               │  │    main · 3/4 15:23           │    │
│  nxtcloud-    │  └──────────────────────────────┘    │
│  homepage     │  ┌──────────────────────────────┐    │
│  ● 3 세션     │  │ 불편한걸 서비스로 만들거야     │    │
│               │  │    main · 3/4 12:10           │    │
│  yeonnam      │  └──────────────────────────────┘    │
│  ● 2 세션     │  ┌──────────────────────────────┐    │
│               │  │ 클로드 코드에 대해 잘쓰고...   │    │
│  certi-nav    │  │    master · 3/3 09:45         │    │
│  ● 1 세션     │  └──────────────────────────────┘    │
│               │                                      │
│   (세로 스크롤) │              (세로 스크롤)            │
├───────────────┴──────────────────────────────────────┤
│  전체 12개 세션  │  핀 2개             Quit ClaudeHub  │
└──────────────────────────────────────────────────────┘
```

### 좌측 사이드바 (30%)
- 프로젝트 목록 (세로 스크롤)
- 선택된 프로젝트 하이라이트
- 프로젝트명 + 세션 수 표시

### 우측 세션 영역 (70%)
- 선택된 프로젝트의 세션 카드 목록 (세로 스크롤)
- 핀된 세션 상단 고정
- 카드: 세션 제목 (최대 2줄) + 시간 + git 브랜치

### 카드 인터랙션
- **클릭**: 선택한 터미널에서 resume 실행
- **호버**: 약간 확대 + 그림자
- **우클릭**: 핀/언핀, 세션 삭제, 세션 ID 복사

## Core Features

### 1. 터미널 Resume 실행
- AppleScript로 터미널 제어
- Terminal.app: `tell application "Terminal" to do script "cd /path && claude --resume <id>"`
- iTerm2: iTerm2 AppleScript API
- Warp / Ghostty: open + CLI integration
- 설정에서 기본 터미널 선택

### 2. 세션 검색
- 모든 프로젝트에서 세션 제목, 프로젝트명으로 필터
- 프로젝트 탭 선택과 무관하게 전체 검색

### 3. 세션 삭제
- 우클릭 → "세션 삭제" → 확인 다이얼로그
- `.jsonl` 파일 + 관련 디렉토리 삭제

### 4. 핀/북마크
- 우클릭 → "핀 고정/해제"
- 프로젝트 내 상단 고정
- UserDefaults에 저장

### 5. 자동 새로고침
- FSEvents로 `~/.claude/projects/` 감시
- 변경 감지 시 해당 프로젝트만 리파싱

## Settings
- 터미널 선택: Terminal.app / iTerm2 / Warp / Ghostty
- 자동 새로고침 간격: 5초 / 10초 / 30초 / 수동
- 로그인 시 자동 시작

## MVP Scope

### 포함
- 세션 목록 표시 (프로젝트별 분류)
- 클릭 resume (터미널 선택 가능)
- 세션 검색/필터
- 핀/북마크
- 세션 삭제

### 제외 (v2)
- 세션 자동 정리
- 세션 통계/분석
- 세션 내용 미리보기
- 여러 세션 동시 resume
- 키보드 단축키
