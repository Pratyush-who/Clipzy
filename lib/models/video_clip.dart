import 'dart:io';

class VideoClip {
  final String id;
  final File file;
  final Duration startTrim;
  final Duration endTrim;
  final Duration originalDuration;
  final double trackPosition;
  final int width;
  final int height;

  VideoClip({
    required this.id,
    required this.file,
    required this.startTrim,
    required this.endTrim,
    required this.originalDuration,
    this.trackPosition = 0.0,
    this.width = 1920,
    this.height = 1080,
  });

  Duration get trimmedDuration => endTrim - startTrim;

  VideoClip copyWith({
    String? id,
    File? file,
    Duration? startTrim,
    Duration? endTrim,
    Duration? originalDuration,
    double? trackPosition,
    int? width,
    int? height,
  }) {
    return VideoClip(
      id: id ?? this.id,
      file: file ?? this.file,
      startTrim: startTrim ?? this.startTrim,
      endTrim: endTrim ?? this.endTrim,
      originalDuration: originalDuration ?? this.originalDuration,
      trackPosition: trackPosition ?? this.trackPosition,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}
