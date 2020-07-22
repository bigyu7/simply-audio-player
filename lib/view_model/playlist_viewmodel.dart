import 'package:flutter/foundation.dart';
import 'package:simply_audio_player/model/config.dart';
import 'package:simply_audio_player/model/play_mode.dart';
import 'package:simply_audio_player/model/playlist.dart';
import 'package:simply_audio_player/service/config_storage_service.dart';
import 'package:simply_audio_player/service/playlist_storege_service.dart';
import 'package:simply_audio_player/service/service_locator.dart';
import 'package:simply_audio_player/view_model/player_viewmodel.dart';

class PlayListViewModel extends ChangeNotifier implements PlayListInterface {
  final ConfigStorageService _configStorageService = serviceLocator<ConfigStorageService>();
  final PlaylistStorageService _playListStorageService = serviceLocator<PlaylistStorageService>();
  final PlayerViewModel _playerViewModel = serviceLocator<PlayerViewModel>();
  final List<PlayStrategy> _playStrategys = [];

  PlayList _playList;
  //String _playListFilePath;

  int _currentTraceIndex;
  PlayMode _playMode;

  PlayListViewModel() {
    _currentTraceIndex=-1;
    _playStrategys.add(InOrderPlayStrategy(this));
    _playStrategys.add(RepeatPlayStrategy(this));
    _playStrategys.add(RepeatOnePlayStrategy(this));
    _playStrategys.add(ShufflePlayStrategy(this));
  }

  List<PlayListItem> get traces => _playList==null?[]:_playList.traces;
  String get name => _playList==null?'':_playList.name;

  get isPlaying => _playerViewModel.isPlaying;

  @override
  int tracesCount() => _playList==null?0:_playList.tracesCount;

  @override
  int currentTraceIndex() => _currentTraceIndex??-1;
  bool isCurrentTrace(int index) => _currentTraceIndex==index;

  PlayMode get playMode => _playMode??PlayMode.in_order;
  PlayStrategy get playStrategy => _playStrategys[playMode.index%_playStrategys.length];

  void nextPlayMode() {
    playStrategy.reset();
    PlayMode currentMode = playMode;
    int index = (currentMode.index + 1) % PlayMode.values.length;
    _playMode = PlayMode.values[index];
    notifyListeners();
    _saveConfig();
  }

  void add(PlayListItem item) {
    // 如果已经在列表中，就不添加
    if(_playList.add(item)) {
      notifyListeners();
      _savePlayList();
    }
  }

  Future<PlayList> _loadPlayListFromFile(String playListFilePath) async {
    _playList = await _playListStorageService.loadPlayList(playListFilePath);
    notifyListeners();
    return _playList;
  }

  void _savePlayList() {
    _playListStorageService.savePlayList(_playList);
  }

  Future loadFromConfig() async {
    Config config = await _configStorageService.loadConfig();
    _playMode = config.playMode;
    return _loadPlayListFromFile(config.playListFilePath);
  }

  Future _saveConfig() async {
    Config config = Config();
    config.playMode = this.playMode;
    config.playListFilePath = _playList.filePath;
    await _configStorageService.saveConfig(config);
  }

  Future changeName(String newName) async {
    if(newName==null||newName.isEmpty||newName==_playList.name) return;
    //_playList.name=newName;

    //print('** changeName() - '+_playList.name+' => '+newName);

    await _playListStorageService.renamePlayList(_playList, newName);
    await _saveConfig();
    notifyListeners();
  }

  void playIndex(int index) {
    _currentTraceIndex = -1;
    if(tracesCount()==0) return;

    if(index<0) _currentTraceIndex=0;
    else _currentTraceIndex = (index%tracesCount());

    PlayListItem item = _playList.getByPosition(_currentTraceIndex);
    if(item==null) return;

    _playerViewModel.playLocalFile(item.file, this.next);
    notifyListeners();
  }

  void play() {
    int index = playStrategy.play();
    print('playStrategy: '+playStrategy.runtimeType.toString()+', play() - '+index.toString());
    if(index<0) return;
    playIndex(index);
  }

  void next() {
    int index = playStrategy.next();
    print('playStrategy: '+playStrategy.runtimeType.toString()+', next() - '+index.toString() + ', currentIndex: '+_currentTraceIndex.toString());
    if(index<0) return;
    playIndex(index);
  }

  void previous() {
    int index = playStrategy.previous();
    print('playStrategy: '+playStrategy.runtimeType.toString()+', previous() - '+index.toString() + ', currentIndex: '+_currentTraceIndex.toString());
    if(index<0) return;
    playIndex(index);
  }

  bool canPrevious() => playStrategy.canPrevious();

  bool canNext() => playStrategy.canNext();

  bool canPlay() => playStrategy.canPlay();

  void playOrPause() {
    if(_playerViewModel.isPlaying) {
      _playerViewModel.pause();
    } else if(_playerViewModel.isPaused) {
      _playerViewModel.play();
    } else if(_playerViewModel.canPlay)  {
      _playerViewModel.play();
    } else {
      play();
    }
  }

  ///
  /// 移除index位置处的playlistitem
  Future removePlayListItemAt(int index) async {
    PlayListItem item = _playList.removePlayListItemAt(index);
    if(item==null) return;

    // 通知strategy，可能需要调整
    playStrategy.onItemRemovedAt(index);

    // 如果是当前在播放的，停止并播放下一首
    if(_currentTraceIndex==index) {
      if(_playerViewModel.isPlaying && tracesCount() > 0) {
        _playerViewModel.stop();
        play();
      } else {
        _currentTraceIndex = -1;
        _playerViewModel.reset();
      }
    } else if(index<_currentTraceIndex) {   // 如果是当前播放前面的，需要调整当前播放序号
      _currentTraceIndex--;
      if(_currentTraceIndex<0) _playerViewModel.reset();
    }

    _savePlayList();
    notifyListeners();
  }

}
