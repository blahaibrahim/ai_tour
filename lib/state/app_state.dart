import 'dart:async';
import 'package:flutter/material.dart';
import '../models/location.dart';

class ChatMessage {
  final String role;
  final String text;
  ChatMessage(this.role, this.text);
}

class AppState extends ChangeNotifier {
  String screen = 'map';
  double radiusKm = 25.0;
  String prompt = '';
  List<String> selectedRegions = List.from(regions);
  int thinkIdx = 0;
  List<Location> queue = [];
  int currentIndex = 0;
  List<Location> accepted = [];
  List<Location> rejected = [];
  
  Location? detailLoc;
  String? detailAnswer;

  bool modifyMode = false;
  bool askPanelOpen = false;
  List<ChatMessage> aiConversation = [];
  
  bool routeAccepted = false;
  List<Task> tasks = [];
  int currentStopIdx = 0;
  int points = 0;

  bool videoPlaying = false;
  String folderSearch = '';

  List<Artifact> capturedArtifacts = [];

  Timer? _thinkTimer;

  static const List<String> thinkingMessages = [
    "Reading your radius…",
    "Checking the Casbah's alleys…",
    "Cross-referencing Constantine's bridges…",
    "Matching Djemila and Timgad's ruins…",
    "Scanning the Tassili plateau…",
    "Ranking spots against your prompt…"
  ];

  void setScreen(String s) {
    screen = s;
    notifyListeners();
  }

  void toggleRegion(String name) {
    if (selectedRegions.contains(name)) {
      selectedRegions.remove(name);
    } else {
      selectedRegions.add(name);
    }
    notifyListeners();
  }

  void setRadius(double val) {
    radiusKm = val;
    notifyListeners();
  }

  void setPrompt(String val) {
    prompt = val;
    notifyListeners();
  }

  void onGenerate() {
    screen = 'thinking';
    thinkIdx = 0;
    notifyListeners();

    _thinkTimer = Timer.periodic(const Duration(milliseconds: 850), (timer) {
      thinkIdx = (thinkIdx + 1) % thinkingMessages.length;
      notifyListeners();
    });

    Future.delayed(const Duration(milliseconds: 3200), () {
      _thinkTimer?.cancel();
      List<Location> filtered = selectedRegions.isNotEmpty
          ? allLocations.where((l) => selectedRegions.contains(l.region)).toList()
          : List.from(allLocations);
      queue = filtered.isNotEmpty ? filtered : List.from(allLocations);
      currentIndex = 0;
      accepted = [];
      rejected = [];
      screen = 'swipe';
      notifyListeners();
    });
  }

  void onBackToMap() {
    _thinkTimer?.cancel();
    screen = 'map';
    notifyListeners();
  }

  Location? getCurrentLoc() {
    if (currentIndex >= 0 && currentIndex < queue.length) {
      return queue[currentIndex];
    }
    return null;
  }

  void commitSwipe(bool isAccept) {
    final loc = getCurrentLoc();
    if (loc == null) return;
    
    if (isAccept) {
      accepted.add(loc);
    } else {
      rejected.add(loc);
    }
    currentIndex++;
    if (currentIndex >= queue.length) {
      screen = 'result';
    }
    notifyListeners();
  }

  void openDetail(Location loc) {
    detailLoc = loc;
    detailAnswer = null;
    notifyListeners();
  }

  void closeDetail() {
    detailLoc = null;
    detailAnswer = null;
    notifyListeners();
  }

  void askQuestion(String answer) {
    detailAnswer = answer;
    notifyListeners();
  }

  void onDetailAccept() {
    commitSwipe(true);
    closeDetail();
  }

  void onDetailReject() {
    commitSwipe(false);
    closeDetail();
  }

  void toggleModify() {
    modifyMode = !modifyMode;
    notifyListeners();
  }

  void toggleAskPanel() {
    askPanelOpen = !askPanelOpen;
    notifyListeners();
  }

  void sendAIChange(String text) {
    if (text.trim().isEmpty) return;
    aiConversation.add(ChatMessage('user', text));
    aiConversation.add(ChatMessage('ai', "Noted — I'll weight the next suggestions toward that."));
    notifyListeners();
  }

  void moveStop(int idx, int dir) {
    final j = idx + dir;
    if (j < 0 || j >= accepted.length) return;
    final tmp = accepted[idx];
    accepted[idx] = accepted[j];
    accepted[j] = tmp;
    notifyListeners();
  }

  void togglePlay() {
    videoPlaying = !videoPlaying;
    notifyListeners();
  }

  void onAcceptRoute() {
    tasks = accepted.map((l) => Task(type: l.task.type, label: l.task.label, points: 30)).toList();
    screen = 'overview';
    routeAccepted = true;
    currentStopIdx = 0;
    notifyListeners();
  }

  void onCompleteTask() {
    if (currentStopIdx >= tasks.length) return;
    final t = tasks[currentStopIdx];
    if (t.state == 'done') return;
    t.state = 'done';
    points += t.points;
    notifyListeners();
  }

  void onAdvanceStop() {
    if (currentStopIdx < accepted.length - 1) {
      currentStopIdx++;
      notifyListeners();
    }
  }

  void onNavHome() {
    screen = routeAccepted ? 'overview' : 'map';
    notifyListeners();
  }

  /// Adds a photo captured with the device camera to the folder. If it was
  /// taken while a scan/video task was still pending on the current stop,
  /// completing the capture also banks that task's points.
  void addCapturedArtifact(String filePath) {
    Location? currentLoc;
    Task? currentTask;
    if (routeAccepted && currentStopIdx < accepted.length) {
      currentLoc = accepted[currentStopIdx];
      currentTask = currentStopIdx < tasks.length ? tasks[currentStopIdx] : null;
    }

    capturedArtifacts.insert(
      0,
      Artifact(
        id: 'capture-${DateTime.now().millisecondsSinceEpoch}',
        name: currentLoc?.name ?? 'Your capture',
        region: currentLoc?.region ?? 'On the go',
        kindLabel: currentTask?.type == 'video' ? 'Video' : 'Scan',
        photoUrl: filePath,
        isLocalFile: true,
      ),
    );

    if (currentTask != null && currentTask.state == 'pending') {
      onCompleteTask();
    } else {
      notifyListeners();
    }
  }
}
