import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

late List<CameraDescription> cameras;

T? _ambiguate<T>(T? value) => value;

void main() async {
  await GetStorage.init();

  await AwaitBindings().dependencies();

  WidgetsFlutterBinding.ensureInitialized();

  cameras = await availableCameras();

  runApp(const MyApp());
}

class AwaitBindings extends Bindings {
  @override
  Future<void> dependencies() async {
    await Get.putAsync(() async => AppController(), permanent: true);
  }
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return const GetMaterialApp(home: MediaListScreen());
  }
}

class AppController extends GetxController {
  final RxList<MediaFile> _mediaFileList = <MediaFile>[].obs;
  List<MediaFile> get mediaFileList => _mediaFileList;
  void setMediaFiles(List<MediaFile> list) {
    _mediaFileList.assignAll(list);
    update();
  }

  void addFile(MediaFile file) {
    _mediaFileList.add(file);
    update();
  }

  void removeFile(MediaFile file) {
    _mediaFileList.remove(file);
    update();
  }

  void updateItem(MediaFile file) {
    addFile(file);
    file.vpc = null;
    removeFile(file);
  }
}

class MediaFile {
  String path;
  String fileName;
  String time;
  int totalBytes;
  VideoPlayerController? vpc;
  MediaFile({
    required this.path,
    required this.fileName,
    required this.time,
    required this.totalBytes,
    this.vpc,
  });

  Map<String, dynamic> toMap() {
    return {
      'path': path,
      'fileName': fileName,
      'time': time,
      'totalBytes': totalBytes,
    };
  }

  factory MediaFile.fromMap(Map<String, dynamic> map) {
    return MediaFile(
        path: map['path'] ?? '',
        fileName: map['fileName'] ?? '',
        time: map['time'] ?? '',
        totalBytes: map['totalBytes'] ?? 0);
  }
}

class MediaListScreen extends StatefulWidget {
  const MediaListScreen({Key? key}) : super(key: key);

  @override
  State<MediaListScreen> createState() => _MediaListScreenState();
}

class _MediaListScreenState extends State<MediaListScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Media List"),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera),
            onPressed: () {
              Get.to(() => const CaptureScreen());
            },
          ),
        ],
      ),
      body: GetBuilder<AppController>(builder: (app) {
        return ListView.builder(
          itemBuilder: (context, index) => ListTile(
            title: Text(app.mediaFileList[index].fileName),
            subtitle: Text("${app.mediaFileList[index].totalBytes} bytes"),
            leading: SizedBox(
              width: 60,
              height: 60,
              child: app.mediaFileList[index].path.endsWith(".mp4")
                  ? const Icon(Icons.video_camera_back)
                  : Image.file(
                      File(app.mediaFileList[index].path),
                      fit: BoxFit.cover,
                    ),
            ),
          ),
          itemCount: app.mediaFileList.length,
        );
      }),
    );
  }
}

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({Key? key}) : super(key: key);

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? controller;
  VideoPlayerController? videoController;
  final ScrollController _listViewController = ScrollController();
  VoidCallback? videoPlayerListener;
  XFile? imageFile;
  XFile? videoFile;
  int _pointers = 0;
  final AppController app = Get.find();

  @override
  void initState() {
    super.initState();
    _ambiguate(WidgetsBinding.instance)?.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    _ambiguate(WidgetsBinding.instance)?.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = controller;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Capture")),
      body: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(child: _cameraPreviewWidget()),
          _previews,
          _controlRowWidget(),
        ],
      ),
    );
  }

  Widget get _previews => Container(
        height: 120,
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        color: Colors.blue.withOpacity(0.3),
        child: GetBuilder<AppController>(builder: (_app) {
          return ListView.builder(
            controller: _listViewController,
            scrollDirection: Axis.horizontal,
            reverse: true,
            itemBuilder: (context, index) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 5),
              width: 100,
              height: 100,
              child: _app.mediaFileList[index].path.endsWith(".mp4")
                  ? _player(_app.mediaFileList[index])
                  : Image.file(
                      File(_app.mediaFileList[index].path),
                      fit: BoxFit.cover,
                    ),
            ),
            itemCount: _app.mediaFileList.length,
          );
        }),
      );

  Widget _controlRowWidget() {
    final CameraController? cameraController = controller;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: Icon(
              Icons.camera_alt,
              size: 48,
            ),
            onPressed: cameraController != null &&
                    cameraController.value.isInitialized &&
                    !cameraController.value.isRecordingVideo
                ? onTakePictureButtonPressed
                : null,
          ),
          IconButton(
            icon: Icon(
              cameraController != null &&
                      cameraController.value.isInitialized &&
                      cameraController.value.isRecordingVideo
                  ? Icons.stop
                  : Icons.videocam,
              size: 48,
            ),
            color: Colors.blue,
            onPressed: cameraController != null &&
                    cameraController.value.isInitialized &&
                    !cameraController.value.isRecordingVideo
                ? onVideoRecordButtonPressed
                : cameraController != null &&
                        cameraController.value.isInitialized &&
                        cameraController.value.isRecordingVideo
                    ? onStopButtonPressed
                    : null,
          ),
        ],
      ),
    );
  }

  Widget _cameraPreviewWidget() {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return const Text("camera not initialized");
    } else {
      return Listener(
        onPointerDown: (_) => _pointers++,
        onPointerUp: (_) => _pointers--,
        child: CameraPreview(controller!),
      );
    }
  }

  Widget _player(MediaFile m) {
    final VideoPlayerController? localVideoController = m.vpc;
    if (localVideoController == null) return Container();
    m.vpc?.play();
    return SizedBox(
      width: 100,
      height: 100,
      child: AspectRatio(
        aspectRatio: localVideoController.value.aspectRatio,
        child: VideoPlayer(localVideoController),
      ),
    );
  }

  Future<void> _initCamera() async {
    final CameraController? oldController = controller;
    if (oldController != null) {
      controller = null;
      await oldController.dispose();
    }

    final CameraController cameraController = CameraController(
      cameras[0],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    controller = cameraController;

    cameraController.addListener(() {
      if (mounted) {
        setState(() {});
      }
      if (cameraController.value.hasError) {
        showInSnackBar('Camera error ${cameraController.value.errorDescription}');
      }
    });

    try {
      await cameraController.initialize();
    } on CameraException catch (e) {
      switch (e.code) {
        case 'CameraAccessDenied':
          showInSnackBar('You have denied camera access.');
          break;
        case 'CameraAccessDeniedWithoutPrompt':
          // iOS only
          showInSnackBar('Please go to Settings app to enable camera access.');
          break;
        case 'CameraAccessRestricted':
          // iOS only
          showInSnackBar('Camera access is restricted.');
          break;
        case 'AudioAccessDenied':
          showInSnackBar('You have denied audio access.');
          break;
        case 'AudioAccessDeniedWithoutPrompt':
          // iOS only
          showInSnackBar('Please go to Settings app to enable audio access.');
          break;
        case 'AudioAccessRestricted':
          // iOS only
          showInSnackBar('Audio access is restricted.');
          break;
        default:
          _showCameraException(e);
          break;
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<XFile?> takePicture() async {
    final CameraController? cameraController = controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return null;
    }

    if (cameraController.value.isTakingPicture) {
      return null;
    }

    try {
      final XFile file = await cameraController.takePicture();
      return file;
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
  }

  void onTakePictureButtonPressed() {
    takePicture().then((XFile? file) async {
      if (mounted) {
        setState(() {
          imageFile = file;
          videoController?.dispose();
          videoController = null;
        });
        if (file != null) {
          // showInSnackBar('Picture saved to ${file.path}');
          await addMediaToList(file);
          // Get.back();
        }
      }
    });
  }

  Future<void> startVideoRecording() async {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return;
    }

    if (cameraController.value.isRecordingVideo) {
      // A recording is already started, do nothing.
      return;
    }

    try {
      await cameraController.startVideoRecording();
    } on CameraException catch (e) {
      _showCameraException(e);
      return;
    }
  }

  Future<XFile?> stopVideoRecording() async {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isRecordingVideo) {
      return null;
    }

    try {
      return cameraController.stopVideoRecording();
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
  }

  Future<void> _startVideoPlayer(MediaFile file) async {
    final VideoPlayerController vController = VideoPlayerController.file(File(file.path));

    videoPlayerListener = () {
      if (videoController != null) {
        // Refreshing the state to update video player with the correct ratio.
        if (mounted) {
          setState(() {});
        }
        videoController!.removeListener(videoPlayerListener!);
      }
    };
    vController.addListener(videoPlayerListener!);
    await vController.setLooping(true);
    await vController.initialize();
    await videoController?.dispose();
    if (mounted) {
      setState(() {
        imageFile = null;
        videoController = vController;
      });
    }
    file.vpc = vController;
    app.updateItem(file);

    await vController.play();
  }

  void onVideoRecordButtonPressed() {
    startVideoRecording().then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void onStopButtonPressed() {
    stopVideoRecording().then((XFile? file) async {
      if (mounted) {
        setState(() {});
      }
      if (file != null) {
        showInSnackBar('Video recorded to ${file.path}');
        videoFile = file;
        var savedFile = await addMediaToList(file);
        _startVideoPlayer(savedFile!);
      }
    });
  }

  Future<MediaFile?> addMediaToList(XFile? file) async {
    if (file == null) return null;
    String ext = file.path.endsWith(".mp4") ? '.mp4' : '.jpg';
    String time = Utils.getTimeString();
    String path = await Utils.createMediaPath();
    String name = "$time$ext";
    String fullPath = "$path/$name";
    log(fullPath);

    int totalBytes = await file.length();
    await File(fullPath).create(recursive: true);

    await file.saveTo(fullPath);

    MediaFile m = MediaFile(
      path: fullPath,
      fileName: name,
      time: time,
      totalBytes: totalBytes,
    );
    app.addFile(m);
    showInSnackBar('added to controller ${m.time}');
    _listViewController.animateTo(
      app.mediaFileList.length * 120,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    return m;
  }

  void showInSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showCameraException(CameraException e) {
    _logError(e.code, e.description);
    showInSnackBar('Error: ${e.code}\n${e.description}');
  }

  void _logError(String code, String? message) {
    if (message != null) {
      log('Error: $code\nError Message: $message');
    } else {
      log('Error: $code');
    }
  }
}

class Utils {
  static String getTimeString() {
    return DateFormat("yyyyMMddHHmmss").format(DateTime.now());
  }

  static Future<String> createMediaPath() async {
    final Directory extDir = await getApplicationDocumentsDirectory();
    String directoryPath = "${extDir.path}/media/drsa";
    // File newPath = File(directoryPath);
    // if (!(await newPath.exists())) {
    //   await newPath.create(recursive: true);
    // }
    return directoryPath;
  }
}
