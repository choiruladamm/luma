// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'catalog_row.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CatalogRow {

/// `Text#` Gutenberg; URL EPUB & cover dirakit dari sini.
 int get id; String get title; List<CatalogAuthor> get authors; List<String> get subjects; List<String> get bookshelves;/// Tanggal rilis di Gutenberg, `YYYY-MM-DD`. Null kalau kosong.
 String? get issued;
/// Create a copy of CatalogRow
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CatalogRowCopyWith<CatalogRow> get copyWith => _$CatalogRowCopyWithImpl<CatalogRow>(this as CatalogRow, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CatalogRow;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CatalogRow&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.title, _this.title) || other.title == _this.title)&&const DeepCollectionEquality().equals(other.authors, _this.authors)&&const DeepCollectionEquality().equals(other.subjects, _this.subjects)&&const DeepCollectionEquality().equals(other.bookshelves, _this.bookshelves)&&(identical(other.issued, _this.issued) || other.issued == _this.issued));
}


@override
int get hashCode {
  final _this = this as CatalogRow;
  return Object.hash(runtimeType,_this.id,_this.title,const DeepCollectionEquality().hash(_this.authors),const DeepCollectionEquality().hash(_this.subjects),const DeepCollectionEquality().hash(_this.bookshelves),_this.issued);
}

@override
String toString() {
  final _this = this as CatalogRow;
  return 'CatalogRow(id: ${_this.id}, title: ${_this.title}, authors: ${_this.authors}, subjects: ${_this.subjects}, bookshelves: ${_this.bookshelves}, issued: ${_this.issued})';
}


}

/// @nodoc
abstract mixin class $CatalogRowCopyWith<$Res>  {
  factory $CatalogRowCopyWith(CatalogRow value, $Res Function(CatalogRow) _then) = _$CatalogRowCopyWithImpl;
@useResult
$Res call({
 int id, String title, List<CatalogAuthor> authors, List<String> subjects, List<String> bookshelves, String? issued
});




}
/// @nodoc
class _$CatalogRowCopyWithImpl<$Res>
    implements $CatalogRowCopyWith<$Res> {
  _$CatalogRowCopyWithImpl(this._self, this._then);

  final CatalogRow _self;
  final $Res Function(CatalogRow) _then;

/// Create a copy of CatalogRow
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? authors = null,Object? subjects = null,Object? bookshelves = null,Object? issued = freezed,}) {
  return _then(CatalogRow(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,authors: null == authors ? _self.authors : authors // ignore: cast_nullable_to_non_nullable
as List<CatalogAuthor>,subjects: null == subjects ? _self.subjects : subjects // ignore: cast_nullable_to_non_nullable
as List<String>,bookshelves: null == bookshelves ? _self.bookshelves : bookshelves // ignore: cast_nullable_to_non_nullable
as List<String>,issued: freezed == issued ? _self.issued : issued // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [CatalogRow].
extension CatalogRowPatterns on CatalogRow {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CatalogRow value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CatalogRow() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CatalogRow value)  $default,){
final _that = this;
switch (_that) {
case _CatalogRow():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CatalogRow value)?  $default,){
final _that = this;
switch (_that) {
case _CatalogRow() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  String title,  List<CatalogAuthor> authors,  List<String> subjects,  List<String> bookshelves,  String? issued)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CatalogRow() when $default != null:
return $default(_that.id,_that.title,_that.authors,_that.subjects,_that.bookshelves,_that.issued);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  String title,  List<CatalogAuthor> authors,  List<String> subjects,  List<String> bookshelves,  String? issued)  $default,) {final _that = this;
switch (_that) {
case _CatalogRow():
return $default(_that.id,_that.title,_that.authors,_that.subjects,_that.bookshelves,_that.issued);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  String title,  List<CatalogAuthor> authors,  List<String> subjects,  List<String> bookshelves,  String? issued)?  $default,) {final _that = this;
switch (_that) {
case _CatalogRow() when $default != null:
return $default(_that.id,_that.title,_that.authors,_that.subjects,_that.bookshelves,_that.issued);case _:
  return null;

}
}

}

/// @nodoc


class _CatalogRow extends CatalogRow {
  const _CatalogRow({required this.id, required this.title, required  List<CatalogAuthor> authors,  List<String> subjects = const [],  List<String> bookshelves = const [], this.issued}): _authors = authors,_subjects = subjects,_bookshelves = bookshelves,super._();
  

/// `Text#` Gutenberg; URL EPUB & cover dirakit dari sini.
@override final  int id;
@override final  String title;
 final  List<CatalogAuthor> _authors;
@override List<CatalogAuthor> get authors {
  if (_authors is EqualUnmodifiableListView) return _authors;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_authors);
}

 final  List<String> _subjects;
@override@JsonKey() List<String> get subjects {
  if (_subjects is EqualUnmodifiableListView) return _subjects;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_subjects);
}

 final  List<String> _bookshelves;
@override@JsonKey() List<String> get bookshelves {
  if (_bookshelves is EqualUnmodifiableListView) return _bookshelves;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_bookshelves);
}

/// Tanggal rilis di Gutenberg, `YYYY-MM-DD`. Null kalau kosong.
@override final  String? issued;

/// Create a copy of CatalogRow
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CatalogRowCopyWith<_CatalogRow> get copyWith => __$CatalogRowCopyWithImpl<_CatalogRow>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CatalogRow&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&const DeepCollectionEquality().equals(other.authors, _authors)&&const DeepCollectionEquality().equals(other.subjects, _subjects)&&const DeepCollectionEquality().equals(other.bookshelves, _bookshelves)&&(identical(other.issued, issued) || other.issued == issued));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,title,const DeepCollectionEquality().hash(_authors),const DeepCollectionEquality().hash(_subjects),const DeepCollectionEquality().hash(_bookshelves),issued);
}

@override
String toString() {
    return 'CatalogRow(id: $id, title: $title, authors: $authors, subjects: $subjects, bookshelves: $bookshelves, issued: $issued)';
}


}

/// @nodoc
abstract mixin class _$CatalogRowCopyWith<$Res> implements $CatalogRowCopyWith<$Res> {
  factory _$CatalogRowCopyWith(_CatalogRow value, $Res Function(_CatalogRow) _then) = __$CatalogRowCopyWithImpl;
@override @useResult
$Res call({
 int id, String title, List<CatalogAuthor> authors, List<String> subjects, List<String> bookshelves, String? issued
});




}
/// @nodoc
class __$CatalogRowCopyWithImpl<$Res>
    implements _$CatalogRowCopyWith<$Res> {
  __$CatalogRowCopyWithImpl(this._self, this._then);

  final _CatalogRow _self;
  final $Res Function(_CatalogRow) _then;

/// Create a copy of CatalogRow
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? authors = null,Object? subjects = null,Object? bookshelves = null,Object? issued = freezed,}) {
  return _then(_CatalogRow(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,authors: null == authors ? _self._authors : authors // ignore: cast_nullable_to_non_nullable
as List<CatalogAuthor>,subjects: null == subjects ? _self._subjects : subjects // ignore: cast_nullable_to_non_nullable
as List<String>,bookshelves: null == bookshelves ? _self._bookshelves : bookshelves // ignore: cast_nullable_to_non_nullable
as List<String>,issued: freezed == issued ? _self.issued : issued // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$CatalogAuthor {

 String get name; int? get birth; int? get death;
/// Create a copy of CatalogAuthor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CatalogAuthorCopyWith<CatalogAuthor> get copyWith => _$CatalogAuthorCopyWithImpl<CatalogAuthor>(this as CatalogAuthor, _$identity);

  /// Serializes this CatalogAuthor to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as CatalogAuthor;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CatalogAuthor&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.birth, _this.birth) || other.birth == _this.birth)&&(identical(other.death, _this.death) || other.death == _this.death));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as CatalogAuthor;
  return Object.hash(runtimeType,_this.name,_this.birth,_this.death);
}

@override
String toString() {
  final _this = this as CatalogAuthor;
  return 'CatalogAuthor(name: ${_this.name}, birth: ${_this.birth}, death: ${_this.death})';
}


}

/// @nodoc
abstract mixin class $CatalogAuthorCopyWith<$Res>  {
  factory $CatalogAuthorCopyWith(CatalogAuthor value, $Res Function(CatalogAuthor) _then) = _$CatalogAuthorCopyWithImpl;
@useResult
$Res call({
 String name, int? birth, int? death
});




}
/// @nodoc
class _$CatalogAuthorCopyWithImpl<$Res>
    implements $CatalogAuthorCopyWith<$Res> {
  _$CatalogAuthorCopyWithImpl(this._self, this._then);

  final CatalogAuthor _self;
  final $Res Function(CatalogAuthor) _then;

/// Create a copy of CatalogAuthor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? birth = freezed,Object? death = freezed,}) {
  return _then(CatalogAuthor(
null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,birth: freezed == birth ? _self.birth : birth // ignore: cast_nullable_to_non_nullable
as int?,death: freezed == death ? _self.death : death // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [CatalogAuthor].
extension CatalogAuthorPatterns on CatalogAuthor {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CatalogAuthor value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CatalogAuthor() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CatalogAuthor value)  $default,){
final _that = this;
switch (_that) {
case _CatalogAuthor():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CatalogAuthor value)?  $default,){
final _that = this;
switch (_that) {
case _CatalogAuthor() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  int? birth,  int? death)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CatalogAuthor() when $default != null:
return $default(_that.name,_that.birth,_that.death);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  int? birth,  int? death)  $default,) {final _that = this;
switch (_that) {
case _CatalogAuthor():
return $default(_that.name,_that.birth,_that.death);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  int? birth,  int? death)?  $default,) {final _that = this;
switch (_that) {
case _CatalogAuthor() when $default != null:
return $default(_that.name,_that.birth,_that.death);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CatalogAuthor implements CatalogAuthor {
  const _CatalogAuthor(this.name, {this.birth, this.death});
  factory _CatalogAuthor.fromJson(Map<String, dynamic> json) => _$CatalogAuthorFromJson(json);

@override final  String name;
@override final  int? birth;
@override final  int? death;

/// Create a copy of CatalogAuthor
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CatalogAuthorCopyWith<_CatalogAuthor> get copyWith => __$CatalogAuthorCopyWithImpl<_CatalogAuthor>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CatalogAuthorToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CatalogAuthor&&(identical(other.name, name) || other.name == name)&&(identical(other.birth, birth) || other.birth == birth)&&(identical(other.death, death) || other.death == death));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,name,birth,death);
}

@override
String toString() {
    return 'CatalogAuthor(name: $name, birth: $birth, death: $death)';
}


}

/// @nodoc
abstract mixin class _$CatalogAuthorCopyWith<$Res> implements $CatalogAuthorCopyWith<$Res> {
  factory _$CatalogAuthorCopyWith(_CatalogAuthor value, $Res Function(_CatalogAuthor) _then) = __$CatalogAuthorCopyWithImpl;
@override @useResult
$Res call({
 String name, int? birth, int? death
});




}
/// @nodoc
class __$CatalogAuthorCopyWithImpl<$Res>
    implements _$CatalogAuthorCopyWith<$Res> {
  __$CatalogAuthorCopyWithImpl(this._self, this._then);

  final _CatalogAuthor _self;
  final $Res Function(_CatalogAuthor) _then;

/// Create a copy of CatalogAuthor
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? birth = freezed,Object? death = freezed,}) {
  return _then(_CatalogAuthor(
null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,birth: freezed == birth ? _self.birth : birth // ignore: cast_nullable_to_non_nullable
as int?,death: freezed == death ? _self.death : death // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
