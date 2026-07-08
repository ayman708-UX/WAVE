// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'community_playlist.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CommunityPlaylist {

 String get id; String get userId; String get creatorName; DeezerPlaylist get playlist; List<DeezerTrack> get tracks; DateTime get createdAt;
/// Create a copy of CommunityPlaylist
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CommunityPlaylistCopyWith<CommunityPlaylist> get copyWith => _$CommunityPlaylistCopyWithImpl<CommunityPlaylist>(this as CommunityPlaylist, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CommunityPlaylist&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.creatorName, creatorName) || other.creatorName == creatorName)&&(identical(other.playlist, playlist) || other.playlist == playlist)&&const DeepCollectionEquality().equals(other.tracks, tracks)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,userId,creatorName,playlist,const DeepCollectionEquality().hash(tracks),createdAt);

@override
String toString() {
  return 'CommunityPlaylist(id: $id, userId: $userId, creatorName: $creatorName, playlist: $playlist, tracks: $tracks, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $CommunityPlaylistCopyWith<$Res>  {
  factory $CommunityPlaylistCopyWith(CommunityPlaylist value, $Res Function(CommunityPlaylist) _then) = _$CommunityPlaylistCopyWithImpl;
@useResult
$Res call({
 String id, String userId, String creatorName, DeezerPlaylist playlist, List<DeezerTrack> tracks, DateTime createdAt
});


$DeezerPlaylistCopyWith<$Res> get playlist;

}
/// @nodoc
class _$CommunityPlaylistCopyWithImpl<$Res>
    implements $CommunityPlaylistCopyWith<$Res> {
  _$CommunityPlaylistCopyWithImpl(this._self, this._then);

  final CommunityPlaylist _self;
  final $Res Function(CommunityPlaylist) _then;

/// Create a copy of CommunityPlaylist
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? userId = null,Object? creatorName = null,Object? playlist = null,Object? tracks = null,Object? createdAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,creatorName: null == creatorName ? _self.creatorName : creatorName // ignore: cast_nullable_to_non_nullable
as String,playlist: null == playlist ? _self.playlist : playlist // ignore: cast_nullable_to_non_nullable
as DeezerPlaylist,tracks: null == tracks ? _self.tracks : tracks // ignore: cast_nullable_to_non_nullable
as List<DeezerTrack>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}
/// Create a copy of CommunityPlaylist
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeezerPlaylistCopyWith<$Res> get playlist {
  
  return $DeezerPlaylistCopyWith<$Res>(_self.playlist, (value) {
    return _then(_self.copyWith(playlist: value));
  });
}
}


/// Adds pattern-matching-related methods to [CommunityPlaylist].
extension CommunityPlaylistPatterns on CommunityPlaylist {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CommunityPlaylist value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CommunityPlaylist() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CommunityPlaylist value)  $default,){
final _that = this;
switch (_that) {
case _CommunityPlaylist():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CommunityPlaylist value)?  $default,){
final _that = this;
switch (_that) {
case _CommunityPlaylist() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String userId,  String creatorName,  DeezerPlaylist playlist,  List<DeezerTrack> tracks,  DateTime createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CommunityPlaylist() when $default != null:
return $default(_that.id,_that.userId,_that.creatorName,_that.playlist,_that.tracks,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String userId,  String creatorName,  DeezerPlaylist playlist,  List<DeezerTrack> tracks,  DateTime createdAt)  $default,) {final _that = this;
switch (_that) {
case _CommunityPlaylist():
return $default(_that.id,_that.userId,_that.creatorName,_that.playlist,_that.tracks,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String userId,  String creatorName,  DeezerPlaylist playlist,  List<DeezerTrack> tracks,  DateTime createdAt)?  $default,) {final _that = this;
switch (_that) {
case _CommunityPlaylist() when $default != null:
return $default(_that.id,_that.userId,_that.creatorName,_that.playlist,_that.tracks,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc


class _CommunityPlaylist implements CommunityPlaylist {
  const _CommunityPlaylist({required this.id, required this.userId, required this.creatorName, required this.playlist, required final  List<DeezerTrack> tracks, required this.createdAt}): _tracks = tracks;
  

@override final  String id;
@override final  String userId;
@override final  String creatorName;
@override final  DeezerPlaylist playlist;
 final  List<DeezerTrack> _tracks;
@override List<DeezerTrack> get tracks {
  if (_tracks is EqualUnmodifiableListView) return _tracks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tracks);
}

@override final  DateTime createdAt;

/// Create a copy of CommunityPlaylist
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CommunityPlaylistCopyWith<_CommunityPlaylist> get copyWith => __$CommunityPlaylistCopyWithImpl<_CommunityPlaylist>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CommunityPlaylist&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.creatorName, creatorName) || other.creatorName == creatorName)&&(identical(other.playlist, playlist) || other.playlist == playlist)&&const DeepCollectionEquality().equals(other._tracks, _tracks)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,userId,creatorName,playlist,const DeepCollectionEquality().hash(_tracks),createdAt);

@override
String toString() {
  return 'CommunityPlaylist(id: $id, userId: $userId, creatorName: $creatorName, playlist: $playlist, tracks: $tracks, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$CommunityPlaylistCopyWith<$Res> implements $CommunityPlaylistCopyWith<$Res> {
  factory _$CommunityPlaylistCopyWith(_CommunityPlaylist value, $Res Function(_CommunityPlaylist) _then) = __$CommunityPlaylistCopyWithImpl;
@override @useResult
$Res call({
 String id, String userId, String creatorName, DeezerPlaylist playlist, List<DeezerTrack> tracks, DateTime createdAt
});


@override $DeezerPlaylistCopyWith<$Res> get playlist;

}
/// @nodoc
class __$CommunityPlaylistCopyWithImpl<$Res>
    implements _$CommunityPlaylistCopyWith<$Res> {
  __$CommunityPlaylistCopyWithImpl(this._self, this._then);

  final _CommunityPlaylist _self;
  final $Res Function(_CommunityPlaylist) _then;

/// Create a copy of CommunityPlaylist
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? userId = null,Object? creatorName = null,Object? playlist = null,Object? tracks = null,Object? createdAt = null,}) {
  return _then(_CommunityPlaylist(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,creatorName: null == creatorName ? _self.creatorName : creatorName // ignore: cast_nullable_to_non_nullable
as String,playlist: null == playlist ? _self.playlist : playlist // ignore: cast_nullable_to_non_nullable
as DeezerPlaylist,tracks: null == tracks ? _self._tracks : tracks // ignore: cast_nullable_to_non_nullable
as List<DeezerTrack>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

/// Create a copy of CommunityPlaylist
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DeezerPlaylistCopyWith<$Res> get playlist {
  
  return $DeezerPlaylistCopyWith<$Res>(_self.playlist, (value) {
    return _then(_self.copyWith(playlist: value));
  });
}
}

// dart format on
