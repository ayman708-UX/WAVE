// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'player_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PlayerState {

 PlaybackStatus get status; DeezerTrack? get currentTrack; Duration get position; Duration get duration; Duration get buffered; bool get shuffle; RepeatMode get repeat; double get volume; double get speed; int get crossfadeSeconds; Duration get transitionDuration; String? get errorMessage;
/// Create a copy of PlayerState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlayerStateCopyWith<PlayerState> get copyWith => _$PlayerStateCopyWithImpl<PlayerState>(this as PlayerState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerState&&(identical(other.status, status) || other.status == status)&&(identical(other.currentTrack, currentTrack) || other.currentTrack == currentTrack)&&(identical(other.position, position) || other.position == position)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.buffered, buffered) || other.buffered == buffered)&&(identical(other.shuffle, shuffle) || other.shuffle == shuffle)&&(identical(other.repeat, repeat) || other.repeat == repeat)&&(identical(other.volume, volume) || other.volume == volume)&&(identical(other.speed, speed) || other.speed == speed)&&(identical(other.crossfadeSeconds, crossfadeSeconds) || other.crossfadeSeconds == crossfadeSeconds)&&(identical(other.transitionDuration, transitionDuration) || other.transitionDuration == transitionDuration)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}


@override
int get hashCode => Object.hash(runtimeType,status,currentTrack,position,duration,buffered,shuffle,repeat,volume,speed,crossfadeSeconds,transitionDuration,errorMessage);

@override
String toString() {
  return 'PlayerState(status: $status, currentTrack: $currentTrack, position: $position, duration: $duration, buffered: $buffered, shuffle: $shuffle, repeat: $repeat, volume: $volume, speed: $speed, crossfadeSeconds: $crossfadeSeconds, transitionDuration: $transitionDuration, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class $PlayerStateCopyWith<$Res>  {
  factory $PlayerStateCopyWith(PlayerState value, $Res Function(PlayerState) _then) = _$PlayerStateCopyWithImpl;
@useResult
$Res call({
 PlaybackStatus status, DeezerTrack? currentTrack, Duration position, Duration duration, Duration buffered, bool shuffle, RepeatMode repeat, double volume, double speed, int crossfadeSeconds, Duration transitionDuration, String? errorMessage
});


$DeezerTrackCopyWith<$Res>? get currentTrack;

}
/// @nodoc
class _$PlayerStateCopyWithImpl<$Res>
    implements $PlayerStateCopyWith<$Res> {
  _$PlayerStateCopyWithImpl(this._self, this._then);

  final PlayerState _self;
  final $Res Function(PlayerState) _then;

/// Create a copy of PlayerState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,Object? currentTrack = freezed,Object? position = null,Object? duration = null,Object? buffered = null,Object? shuffle = null,Object? repeat = null,Object? volume = null,Object? speed = null,Object? crossfadeSeconds = null,Object? transitionDuration = null,Object? errorMessage = freezed,}) {
  return _then(_self.copyWith(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as PlaybackStatus,currentTrack: freezed == currentTrack ? _self.currentTrack : currentTrack // ignore: cast_nullable_to_non_nullable
as DeezerTrack?,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as Duration,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration,buffered: null == buffered ? _self.buffered : buffered // ignore: cast_nullable_to_non_nullable
as Duration,shuffle: null == shuffle ? _self.shuffle : shuffle // ignore: cast_nullable_to_non_nullable
as bool,repeat: null == repeat ? _self.repeat : repeat // ignore: cast_nullable_to_non_nullable
as RepeatMode,volume: null == volume ? _self.volume : volume // ignore: cast_nullable_to_non_nullable
as double,speed: null == speed ? _self.speed : speed // ignore: cast_nullable_to_non_nullable
as double,crossfadeSeconds: null == crossfadeSeconds ? _self.crossfadeSeconds : crossfadeSeconds // ignore: cast_nullable_to_non_nullable
as int,transitionDuration: null == transitionDuration ? _self.transitionDuration : transitionDuration // ignore: cast_nullable_to_non_nullable
as Duration,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of PlayerState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeezerTrackCopyWith<$Res>? get currentTrack {
    if (_self.currentTrack == null) {
    return null;
  }

  return $DeezerTrackCopyWith<$Res>(_self.currentTrack!, (value) {
    return _then(_self.copyWith(currentTrack: value));
  });
}
}


/// Adds pattern-matching-related methods to [PlayerState].
extension PlayerStatePatterns on PlayerState {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PlayerState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PlayerState() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PlayerState value)  $default,){
final _that = this;
switch (_that) {
case _PlayerState():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PlayerState value)?  $default,){
final _that = this;
switch (_that) {
case _PlayerState() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( PlaybackStatus status,  DeezerTrack? currentTrack,  Duration position,  Duration duration,  Duration buffered,  bool shuffle,  RepeatMode repeat,  double volume,  double speed,  int crossfadeSeconds,  Duration transitionDuration,  String? errorMessage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PlayerState() when $default != null:
return $default(_that.status,_that.currentTrack,_that.position,_that.duration,_that.buffered,_that.shuffle,_that.repeat,_that.volume,_that.speed,_that.crossfadeSeconds,_that.transitionDuration,_that.errorMessage);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( PlaybackStatus status,  DeezerTrack? currentTrack,  Duration position,  Duration duration,  Duration buffered,  bool shuffle,  RepeatMode repeat,  double volume,  double speed,  int crossfadeSeconds,  Duration transitionDuration,  String? errorMessage)  $default,) {final _that = this;
switch (_that) {
case _PlayerState():
return $default(_that.status,_that.currentTrack,_that.position,_that.duration,_that.buffered,_that.shuffle,_that.repeat,_that.volume,_that.speed,_that.crossfadeSeconds,_that.transitionDuration,_that.errorMessage);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( PlaybackStatus status,  DeezerTrack? currentTrack,  Duration position,  Duration duration,  Duration buffered,  bool shuffle,  RepeatMode repeat,  double volume,  double speed,  int crossfadeSeconds,  Duration transitionDuration,  String? errorMessage)?  $default,) {final _that = this;
switch (_that) {
case _PlayerState() when $default != null:
return $default(_that.status,_that.currentTrack,_that.position,_that.duration,_that.buffered,_that.shuffle,_that.repeat,_that.volume,_that.speed,_that.crossfadeSeconds,_that.transitionDuration,_that.errorMessage);case _:
  return null;

}
}

}

/// @nodoc


class _PlayerState implements PlayerState {
  const _PlayerState({this.status = PlaybackStatus.idle, this.currentTrack, this.position = Duration.zero, this.duration = Duration.zero, this.buffered = Duration.zero, this.shuffle = false, this.repeat = RepeatMode.off, this.volume = 1.0, this.speed = 1.0, this.crossfadeSeconds = 0, this.transitionDuration = const Duration(milliseconds: 500), this.errorMessage});
  

@override@JsonKey() final  PlaybackStatus status;
@override final  DeezerTrack? currentTrack;
@override@JsonKey() final  Duration position;
@override@JsonKey() final  Duration duration;
@override@JsonKey() final  Duration buffered;
@override@JsonKey() final  bool shuffle;
@override@JsonKey() final  RepeatMode repeat;
@override@JsonKey() final  double volume;
@override@JsonKey() final  double speed;
@override@JsonKey() final  int crossfadeSeconds;
@override@JsonKey() final  Duration transitionDuration;
@override final  String? errorMessage;

/// Create a copy of PlayerState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlayerStateCopyWith<_PlayerState> get copyWith => __$PlayerStateCopyWithImpl<_PlayerState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PlayerState&&(identical(other.status, status) || other.status == status)&&(identical(other.currentTrack, currentTrack) || other.currentTrack == currentTrack)&&(identical(other.position, position) || other.position == position)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.buffered, buffered) || other.buffered == buffered)&&(identical(other.shuffle, shuffle) || other.shuffle == shuffle)&&(identical(other.repeat, repeat) || other.repeat == repeat)&&(identical(other.volume, volume) || other.volume == volume)&&(identical(other.speed, speed) || other.speed == speed)&&(identical(other.crossfadeSeconds, crossfadeSeconds) || other.crossfadeSeconds == crossfadeSeconds)&&(identical(other.transitionDuration, transitionDuration) || other.transitionDuration == transitionDuration)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}


@override
int get hashCode => Object.hash(runtimeType,status,currentTrack,position,duration,buffered,shuffle,repeat,volume,speed,crossfadeSeconds,transitionDuration,errorMessage);

@override
String toString() {
  return 'PlayerState(status: $status, currentTrack: $currentTrack, position: $position, duration: $duration, buffered: $buffered, shuffle: $shuffle, repeat: $repeat, volume: $volume, speed: $speed, crossfadeSeconds: $crossfadeSeconds, transitionDuration: $transitionDuration, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class _$PlayerStateCopyWith<$Res> implements $PlayerStateCopyWith<$Res> {
  factory _$PlayerStateCopyWith(_PlayerState value, $Res Function(_PlayerState) _then) = __$PlayerStateCopyWithImpl;
@override @useResult
$Res call({
 PlaybackStatus status, DeezerTrack? currentTrack, Duration position, Duration duration, Duration buffered, bool shuffle, RepeatMode repeat, double volume, double speed, int crossfadeSeconds, Duration transitionDuration, String? errorMessage
});


@override $DeezerTrackCopyWith<$Res>? get currentTrack;

}
/// @nodoc
class __$PlayerStateCopyWithImpl<$Res>
    implements _$PlayerStateCopyWith<$Res> {
  __$PlayerStateCopyWithImpl(this._self, this._then);

  final _PlayerState _self;
  final $Res Function(_PlayerState) _then;

/// Create a copy of PlayerState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? currentTrack = freezed,Object? position = null,Object? duration = null,Object? buffered = null,Object? shuffle = null,Object? repeat = null,Object? volume = null,Object? speed = null,Object? crossfadeSeconds = null,Object? transitionDuration = null,Object? errorMessage = freezed,}) {
  return _then(_PlayerState(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as PlaybackStatus,currentTrack: freezed == currentTrack ? _self.currentTrack : currentTrack // ignore: cast_nullable_to_non_nullable
as DeezerTrack?,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as Duration,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration,buffered: null == buffered ? _self.buffered : buffered // ignore: cast_nullable_to_non_nullable
as Duration,shuffle: null == shuffle ? _self.shuffle : shuffle // ignore: cast_nullable_to_non_nullable
as bool,repeat: null == repeat ? _self.repeat : repeat // ignore: cast_nullable_to_non_nullable
as RepeatMode,volume: null == volume ? _self.volume : volume // ignore: cast_nullable_to_non_nullable
as double,speed: null == speed ? _self.speed : speed // ignore: cast_nullable_to_non_nullable
as double,crossfadeSeconds: null == crossfadeSeconds ? _self.crossfadeSeconds : crossfadeSeconds // ignore: cast_nullable_to_non_nullable
as int,transitionDuration: null == transitionDuration ? _self.transitionDuration : transitionDuration // ignore: cast_nullable_to_non_nullable
as Duration,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of PlayerState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeezerTrackCopyWith<$Res>? get currentTrack {
    if (_self.currentTrack == null) {
    return null;
  }

  return $DeezerTrackCopyWith<$Res>(_self.currentTrack!, (value) {
    return _then(_self.copyWith(currentTrack: value));
  });
}
}

// dart format on
