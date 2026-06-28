// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'queue_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$QueueState {

 List<DeezerTrack> get history; List<DeezerTrack> get upcoming; DeezerTrack? get current; bool get shuffled; bool get isRelatedMode; List<DeezerTrack> get originalUpcoming;
/// Create a copy of QueueState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QueueStateCopyWith<QueueState> get copyWith => _$QueueStateCopyWithImpl<QueueState>(this as QueueState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QueueState&&const DeepCollectionEquality().equals(other.history, history)&&const DeepCollectionEquality().equals(other.upcoming, upcoming)&&(identical(other.current, current) || other.current == current)&&(identical(other.shuffled, shuffled) || other.shuffled == shuffled)&&(identical(other.isRelatedMode, isRelatedMode) || other.isRelatedMode == isRelatedMode)&&const DeepCollectionEquality().equals(other.originalUpcoming, originalUpcoming));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(history),const DeepCollectionEquality().hash(upcoming),current,shuffled,isRelatedMode,const DeepCollectionEquality().hash(originalUpcoming));

@override
String toString() {
  return 'QueueState(history: $history, upcoming: $upcoming, current: $current, shuffled: $shuffled, isRelatedMode: $isRelatedMode, originalUpcoming: $originalUpcoming)';
}


}

/// @nodoc
abstract mixin class $QueueStateCopyWith<$Res>  {
  factory $QueueStateCopyWith(QueueState value, $Res Function(QueueState) _then) = _$QueueStateCopyWithImpl;
@useResult
$Res call({
 List<DeezerTrack> history, List<DeezerTrack> upcoming, DeezerTrack? current, bool shuffled, bool isRelatedMode, List<DeezerTrack> originalUpcoming
});


$DeezerTrackCopyWith<$Res>? get current;

}
/// @nodoc
class _$QueueStateCopyWithImpl<$Res>
    implements $QueueStateCopyWith<$Res> {
  _$QueueStateCopyWithImpl(this._self, this._then);

  final QueueState _self;
  final $Res Function(QueueState) _then;

/// Create a copy of QueueState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? history = null,Object? upcoming = null,Object? current = freezed,Object? shuffled = null,Object? isRelatedMode = null,Object? originalUpcoming = null,}) {
  return _then(_self.copyWith(
history: null == history ? _self.history : history // ignore: cast_nullable_to_non_nullable
as List<DeezerTrack>,upcoming: null == upcoming ? _self.upcoming : upcoming // ignore: cast_nullable_to_non_nullable
as List<DeezerTrack>,current: freezed == current ? _self.current : current // ignore: cast_nullable_to_non_nullable
as DeezerTrack?,shuffled: null == shuffled ? _self.shuffled : shuffled // ignore: cast_nullable_to_non_nullable
as bool,isRelatedMode: null == isRelatedMode ? _self.isRelatedMode : isRelatedMode // ignore: cast_nullable_to_non_nullable
as bool,originalUpcoming: null == originalUpcoming ? _self.originalUpcoming : originalUpcoming // ignore: cast_nullable_to_non_nullable
as List<DeezerTrack>,
  ));
}
/// Create a copy of QueueState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeezerTrackCopyWith<$Res>? get current {
    if (_self.current == null) {
    return null;
  }

  return $DeezerTrackCopyWith<$Res>(_self.current!, (value) {
    return _then(_self.copyWith(current: value));
  });
}
}


/// Adds pattern-matching-related methods to [QueueState].
extension QueueStatePatterns on QueueState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QueueState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QueueState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QueueState value)  $default,){
final _that = this;
switch (_that) {
case _QueueState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QueueState value)?  $default,){
final _that = this;
switch (_that) {
case _QueueState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<DeezerTrack> history,  List<DeezerTrack> upcoming,  DeezerTrack? current,  bool shuffled,  bool isRelatedMode,  List<DeezerTrack> originalUpcoming)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QueueState() when $default != null:
return $default(_that.history,_that.upcoming,_that.current,_that.shuffled,_that.isRelatedMode,_that.originalUpcoming);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<DeezerTrack> history,  List<DeezerTrack> upcoming,  DeezerTrack? current,  bool shuffled,  bool isRelatedMode,  List<DeezerTrack> originalUpcoming)  $default,) {final _that = this;
switch (_that) {
case _QueueState():
return $default(_that.history,_that.upcoming,_that.current,_that.shuffled,_that.isRelatedMode,_that.originalUpcoming);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<DeezerTrack> history,  List<DeezerTrack> upcoming,  DeezerTrack? current,  bool shuffled,  bool isRelatedMode,  List<DeezerTrack> originalUpcoming)?  $default,) {final _that = this;
switch (_that) {
case _QueueState() when $default != null:
return $default(_that.history,_that.upcoming,_that.current,_that.shuffled,_that.isRelatedMode,_that.originalUpcoming);case _:
  return null;

}
}

}

/// @nodoc


class _QueueState implements QueueState {
  const _QueueState({final  List<DeezerTrack> history = const <DeezerTrack>[], final  List<DeezerTrack> upcoming = const <DeezerTrack>[], this.current, this.shuffled = false, this.isRelatedMode = false, final  List<DeezerTrack> originalUpcoming = const <DeezerTrack>[]}): _history = history,_upcoming = upcoming,_originalUpcoming = originalUpcoming;
  

 final  List<DeezerTrack> _history;
@override@JsonKey() List<DeezerTrack> get history {
  if (_history is EqualUnmodifiableListView) return _history;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_history);
}

 final  List<DeezerTrack> _upcoming;
@override@JsonKey() List<DeezerTrack> get upcoming {
  if (_upcoming is EqualUnmodifiableListView) return _upcoming;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_upcoming);
}

@override final  DeezerTrack? current;
@override@JsonKey() final  bool shuffled;
@override@JsonKey() final  bool isRelatedMode;
 final  List<DeezerTrack> _originalUpcoming;
@override@JsonKey() List<DeezerTrack> get originalUpcoming {
  if (_originalUpcoming is EqualUnmodifiableListView) return _originalUpcoming;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_originalUpcoming);
}


/// Create a copy of QueueState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QueueStateCopyWith<_QueueState> get copyWith => __$QueueStateCopyWithImpl<_QueueState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _QueueState&&const DeepCollectionEquality().equals(other._history, _history)&&const DeepCollectionEquality().equals(other._upcoming, _upcoming)&&(identical(other.current, current) || other.current == current)&&(identical(other.shuffled, shuffled) || other.shuffled == shuffled)&&(identical(other.isRelatedMode, isRelatedMode) || other.isRelatedMode == isRelatedMode)&&const DeepCollectionEquality().equals(other._originalUpcoming, _originalUpcoming));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_history),const DeepCollectionEquality().hash(_upcoming),current,shuffled,isRelatedMode,const DeepCollectionEquality().hash(_originalUpcoming));

@override
String toString() {
  return 'QueueState(history: $history, upcoming: $upcoming, current: $current, shuffled: $shuffled, isRelatedMode: $isRelatedMode, originalUpcoming: $originalUpcoming)';
}


}

/// @nodoc
abstract mixin class _$QueueStateCopyWith<$Res> implements $QueueStateCopyWith<$Res> {
  factory _$QueueStateCopyWith(_QueueState value, $Res Function(_QueueState) _then) = __$QueueStateCopyWithImpl;
@override @useResult
$Res call({
 List<DeezerTrack> history, List<DeezerTrack> upcoming, DeezerTrack? current, bool shuffled, bool isRelatedMode, List<DeezerTrack> originalUpcoming
});


@override $DeezerTrackCopyWith<$Res>? get current;

}
/// @nodoc
class __$QueueStateCopyWithImpl<$Res>
    implements _$QueueStateCopyWith<$Res> {
  __$QueueStateCopyWithImpl(this._self, this._then);

  final _QueueState _self;
  final $Res Function(_QueueState) _then;

/// Create a copy of QueueState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? history = null,Object? upcoming = null,Object? current = freezed,Object? shuffled = null,Object? isRelatedMode = null,Object? originalUpcoming = null,}) {
  return _then(_QueueState(
history: null == history ? _self._history : history // ignore: cast_nullable_to_non_nullable
as List<DeezerTrack>,upcoming: null == upcoming ? _self._upcoming : upcoming // ignore: cast_nullable_to_non_nullable
as List<DeezerTrack>,current: freezed == current ? _self.current : current // ignore: cast_nullable_to_non_nullable
as DeezerTrack?,shuffled: null == shuffled ? _self.shuffled : shuffled // ignore: cast_nullable_to_non_nullable
as bool,isRelatedMode: null == isRelatedMode ? _self.isRelatedMode : isRelatedMode // ignore: cast_nullable_to_non_nullable
as bool,originalUpcoming: null == originalUpcoming ? _self._originalUpcoming : originalUpcoming // ignore: cast_nullable_to_non_nullable
as List<DeezerTrack>,
  ));
}

/// Create a copy of QueueState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeezerTrackCopyWith<$Res>? get current {
    if (_self.current == null) {
    return null;
  }

  return $DeezerTrackCopyWith<$Res>(_self.current!, (value) {
    return _then(_self.copyWith(current: value));
  });
}
}

// dart format on
