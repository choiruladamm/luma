// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'catalog.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CatalogPage {

 List<CatalogBook> get items; bool get hasMore;/// Jumlah total hasil ("7 hasil"). Null = sumbernya gak tau (populer OPDS).
 int? get total;
/// Create a copy of CatalogPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CatalogPageCopyWith<CatalogPage> get copyWith => _$CatalogPageCopyWithImpl<CatalogPage>(this as CatalogPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CatalogPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CatalogPage&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.hasMore, _this.hasMore) || other.hasMore == _this.hasMore)&&(identical(other.total, _this.total) || other.total == _this.total));
}


@override
int get hashCode {
  final _this = this as CatalogPage;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.items),_this.hasMore,_this.total);
}

@override
String toString() {
  final _this = this as CatalogPage;
  return 'CatalogPage(items: ${_this.items}, hasMore: ${_this.hasMore}, total: ${_this.total})';
}


}

/// @nodoc
abstract mixin class $CatalogPageCopyWith<$Res>  {
  factory $CatalogPageCopyWith(CatalogPage value, $Res Function(CatalogPage) _then) = _$CatalogPageCopyWithImpl;
@useResult
$Res call({
 List<CatalogBook> items, bool hasMore, int? total
});




}
/// @nodoc
class _$CatalogPageCopyWithImpl<$Res>
    implements $CatalogPageCopyWith<$Res> {
  _$CatalogPageCopyWithImpl(this._self, this._then);

  final CatalogPage _self;
  final $Res Function(CatalogPage) _then;

/// Create a copy of CatalogPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? items = null,Object? hasMore = null,Object? total = freezed,}) {
  return _then(CatalogPage(
items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<CatalogBook>,hasMore: null == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool,total: freezed == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [CatalogPage].
extension CatalogPagePatterns on CatalogPage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CatalogPage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CatalogPage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CatalogPage value)  $default,){
final _that = this;
switch (_that) {
case _CatalogPage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CatalogPage value)?  $default,){
final _that = this;
switch (_that) {
case _CatalogPage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<CatalogBook> items,  bool hasMore,  int? total)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CatalogPage() when $default != null:
return $default(_that.items,_that.hasMore,_that.total);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<CatalogBook> items,  bool hasMore,  int? total)  $default,) {final _that = this;
switch (_that) {
case _CatalogPage():
return $default(_that.items,_that.hasMore,_that.total);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<CatalogBook> items,  bool hasMore,  int? total)?  $default,) {final _that = this;
switch (_that) {
case _CatalogPage() when $default != null:
return $default(_that.items,_that.hasMore,_that.total);case _:
  return null;

}
}

}

/// @nodoc


class _CatalogPage implements CatalogPage {
  const _CatalogPage({required  List<CatalogBook> items, required this.hasMore, this.total}): _items = items;
  

 final  List<CatalogBook> _items;
@override List<CatalogBook> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  bool hasMore;
/// Jumlah total hasil ("7 hasil"). Null = sumbernya gak tau (populer OPDS).
@override final  int? total;

/// Create a copy of CatalogPage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CatalogPageCopyWith<_CatalogPage> get copyWith => __$CatalogPageCopyWithImpl<_CatalogPage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CatalogPage&&const DeepCollectionEquality().equals(other.items, _items)&&(identical(other.hasMore, hasMore) || other.hasMore == hasMore)&&(identical(other.total, total) || other.total == total));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_items),hasMore,total);
}

@override
String toString() {
    return 'CatalogPage(items: $items, hasMore: $hasMore, total: $total)';
}


}

/// @nodoc
abstract mixin class _$CatalogPageCopyWith<$Res> implements $CatalogPageCopyWith<$Res> {
  factory _$CatalogPageCopyWith(_CatalogPage value, $Res Function(_CatalogPage) _then) = __$CatalogPageCopyWithImpl;
@override @useResult
$Res call({
 List<CatalogBook> items, bool hasMore, int? total
});




}
/// @nodoc
class __$CatalogPageCopyWithImpl<$Res>
    implements _$CatalogPageCopyWith<$Res> {
  __$CatalogPageCopyWithImpl(this._self, this._then);

  final _CatalogPage _self;
  final $Res Function(_CatalogPage) _then;

/// Create a copy of CatalogPage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? items = null,Object? hasMore = null,Object? total = freezed,}) {
  return _then(_CatalogPage(
items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<CatalogBook>,hasMore: null == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool,total: freezed == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$CatalogBook {

 String get sourceId; String get externalId; String get title; List<CatalogAuthor> get authors; String get coverUrl; String get downloadUrl;
/// Create a copy of CatalogBook
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CatalogBookCopyWith<CatalogBook> get copyWith => _$CatalogBookCopyWithImpl<CatalogBook>(this as CatalogBook, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CatalogBook;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CatalogBook&&(identical(other.sourceId, _this.sourceId) || other.sourceId == _this.sourceId)&&(identical(other.externalId, _this.externalId) || other.externalId == _this.externalId)&&(identical(other.title, _this.title) || other.title == _this.title)&&const DeepCollectionEquality().equals(other.authors, _this.authors)&&(identical(other.coverUrl, _this.coverUrl) || other.coverUrl == _this.coverUrl)&&(identical(other.downloadUrl, _this.downloadUrl) || other.downloadUrl == _this.downloadUrl));
}


@override
int get hashCode {
  final _this = this as CatalogBook;
  return Object.hash(runtimeType,_this.sourceId,_this.externalId,_this.title,const DeepCollectionEquality().hash(_this.authors),_this.coverUrl,_this.downloadUrl);
}

@override
String toString() {
  final _this = this as CatalogBook;
  return 'CatalogBook(sourceId: ${_this.sourceId}, externalId: ${_this.externalId}, title: ${_this.title}, authors: ${_this.authors}, coverUrl: ${_this.coverUrl}, downloadUrl: ${_this.downloadUrl})';
}


}

/// @nodoc
abstract mixin class $CatalogBookCopyWith<$Res>  {
  factory $CatalogBookCopyWith(CatalogBook value, $Res Function(CatalogBook) _then) = _$CatalogBookCopyWithImpl;
@useResult
$Res call({
 String sourceId, String externalId, String title, List<CatalogAuthor> authors, String coverUrl, String downloadUrl
});




}
/// @nodoc
class _$CatalogBookCopyWithImpl<$Res>
    implements $CatalogBookCopyWith<$Res> {
  _$CatalogBookCopyWithImpl(this._self, this._then);

  final CatalogBook _self;
  final $Res Function(CatalogBook) _then;

/// Create a copy of CatalogBook
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sourceId = null,Object? externalId = null,Object? title = null,Object? authors = null,Object? coverUrl = null,Object? downloadUrl = null,}) {
  return _then(CatalogBook(
sourceId: null == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String,externalId: null == externalId ? _self.externalId : externalId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,authors: null == authors ? _self.authors : authors // ignore: cast_nullable_to_non_nullable
as List<CatalogAuthor>,coverUrl: null == coverUrl ? _self.coverUrl : coverUrl // ignore: cast_nullable_to_non_nullable
as String,downloadUrl: null == downloadUrl ? _self.downloadUrl : downloadUrl // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [CatalogBook].
extension CatalogBookPatterns on CatalogBook {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CatalogBook value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CatalogBook() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CatalogBook value)  $default,){
final _that = this;
switch (_that) {
case _CatalogBook():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CatalogBook value)?  $default,){
final _that = this;
switch (_that) {
case _CatalogBook() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String sourceId,  String externalId,  String title,  List<CatalogAuthor> authors,  String coverUrl,  String downloadUrl)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CatalogBook() when $default != null:
return $default(_that.sourceId,_that.externalId,_that.title,_that.authors,_that.coverUrl,_that.downloadUrl);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String sourceId,  String externalId,  String title,  List<CatalogAuthor> authors,  String coverUrl,  String downloadUrl)  $default,) {final _that = this;
switch (_that) {
case _CatalogBook():
return $default(_that.sourceId,_that.externalId,_that.title,_that.authors,_that.coverUrl,_that.downloadUrl);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String sourceId,  String externalId,  String title,  List<CatalogAuthor> authors,  String coverUrl,  String downloadUrl)?  $default,) {final _that = this;
switch (_that) {
case _CatalogBook() when $default != null:
return $default(_that.sourceId,_that.externalId,_that.title,_that.authors,_that.coverUrl,_that.downloadUrl);case _:
  return null;

}
}

}

/// @nodoc


class _CatalogBook implements CatalogBook {
  const _CatalogBook({required this.sourceId, required this.externalId, required this.title, required  List<CatalogAuthor> authors, required this.coverUrl, required this.downloadUrl}): _authors = authors;
  

@override final  String sourceId;
@override final  String externalId;
@override final  String title;
 final  List<CatalogAuthor> _authors;
@override List<CatalogAuthor> get authors {
  if (_authors is EqualUnmodifiableListView) return _authors;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_authors);
}

@override final  String coverUrl;
@override final  String downloadUrl;

/// Create a copy of CatalogBook
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CatalogBookCopyWith<_CatalogBook> get copyWith => __$CatalogBookCopyWithImpl<_CatalogBook>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CatalogBook&&(identical(other.sourceId, sourceId) || other.sourceId == sourceId)&&(identical(other.externalId, externalId) || other.externalId == externalId)&&(identical(other.title, title) || other.title == title)&&const DeepCollectionEquality().equals(other.authors, _authors)&&(identical(other.coverUrl, coverUrl) || other.coverUrl == coverUrl)&&(identical(other.downloadUrl, downloadUrl) || other.downloadUrl == downloadUrl));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sourceId,externalId,title,const DeepCollectionEquality().hash(_authors),coverUrl,downloadUrl);
}

@override
String toString() {
    return 'CatalogBook(sourceId: $sourceId, externalId: $externalId, title: $title, authors: $authors, coverUrl: $coverUrl, downloadUrl: $downloadUrl)';
}


}

/// @nodoc
abstract mixin class _$CatalogBookCopyWith<$Res> implements $CatalogBookCopyWith<$Res> {
  factory _$CatalogBookCopyWith(_CatalogBook value, $Res Function(_CatalogBook) _then) = __$CatalogBookCopyWithImpl;
@override @useResult
$Res call({
 String sourceId, String externalId, String title, List<CatalogAuthor> authors, String coverUrl, String downloadUrl
});




}
/// @nodoc
class __$CatalogBookCopyWithImpl<$Res>
    implements _$CatalogBookCopyWith<$Res> {
  __$CatalogBookCopyWithImpl(this._self, this._then);

  final _CatalogBook _self;
  final $Res Function(_CatalogBook) _then;

/// Create a copy of CatalogBook
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sourceId = null,Object? externalId = null,Object? title = null,Object? authors = null,Object? coverUrl = null,Object? downloadUrl = null,}) {
  return _then(_CatalogBook(
sourceId: null == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String,externalId: null == externalId ? _self.externalId : externalId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,authors: null == authors ? _self._authors : authors // ignore: cast_nullable_to_non_nullable
as List<CatalogAuthor>,coverUrl: null == coverUrl ? _self.coverUrl : coverUrl // ignore: cast_nullable_to_non_nullable
as String,downloadUrl: null == downloadUrl ? _self.downloadUrl : downloadUrl // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$CatalogBookDetail {

 String? get summary; List<String> get subjects; List<String> get bookshelves;/// Ukuran EPUB dalam byte.
 int? get fileSize;/// Tanggal masuk ke sumber (Gutenberg: tanggal rilis digital, bukan
/// tahun terbit asli). ISO 8601.
 String? get issued; String? get wikipediaUrl;
/// Create a copy of CatalogBookDetail
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CatalogBookDetailCopyWith<CatalogBookDetail> get copyWith => _$CatalogBookDetailCopyWithImpl<CatalogBookDetail>(this as CatalogBookDetail, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CatalogBookDetail;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CatalogBookDetail&&(identical(other.summary, _this.summary) || other.summary == _this.summary)&&const DeepCollectionEquality().equals(other.subjects, _this.subjects)&&const DeepCollectionEquality().equals(other.bookshelves, _this.bookshelves)&&(identical(other.fileSize, _this.fileSize) || other.fileSize == _this.fileSize)&&(identical(other.issued, _this.issued) || other.issued == _this.issued)&&(identical(other.wikipediaUrl, _this.wikipediaUrl) || other.wikipediaUrl == _this.wikipediaUrl));
}


@override
int get hashCode {
  final _this = this as CatalogBookDetail;
  return Object.hash(runtimeType,_this.summary,const DeepCollectionEquality().hash(_this.subjects),const DeepCollectionEquality().hash(_this.bookshelves),_this.fileSize,_this.issued,_this.wikipediaUrl);
}

@override
String toString() {
  final _this = this as CatalogBookDetail;
  return 'CatalogBookDetail(summary: ${_this.summary}, subjects: ${_this.subjects}, bookshelves: ${_this.bookshelves}, fileSize: ${_this.fileSize}, issued: ${_this.issued}, wikipediaUrl: ${_this.wikipediaUrl})';
}


}

/// @nodoc
abstract mixin class $CatalogBookDetailCopyWith<$Res>  {
  factory $CatalogBookDetailCopyWith(CatalogBookDetail value, $Res Function(CatalogBookDetail) _then) = _$CatalogBookDetailCopyWithImpl;
@useResult
$Res call({
 String? summary, List<String> subjects, List<String> bookshelves, int? fileSize, String? issued, String? wikipediaUrl
});




}
/// @nodoc
class _$CatalogBookDetailCopyWithImpl<$Res>
    implements $CatalogBookDetailCopyWith<$Res> {
  _$CatalogBookDetailCopyWithImpl(this._self, this._then);

  final CatalogBookDetail _self;
  final $Res Function(CatalogBookDetail) _then;

/// Create a copy of CatalogBookDetail
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? summary = freezed,Object? subjects = null,Object? bookshelves = null,Object? fileSize = freezed,Object? issued = freezed,Object? wikipediaUrl = freezed,}) {
  return _then(CatalogBookDetail(
summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String?,subjects: null == subjects ? _self.subjects : subjects // ignore: cast_nullable_to_non_nullable
as List<String>,bookshelves: null == bookshelves ? _self.bookshelves : bookshelves // ignore: cast_nullable_to_non_nullable
as List<String>,fileSize: freezed == fileSize ? _self.fileSize : fileSize // ignore: cast_nullable_to_non_nullable
as int?,issued: freezed == issued ? _self.issued : issued // ignore: cast_nullable_to_non_nullable
as String?,wikipediaUrl: freezed == wikipediaUrl ? _self.wikipediaUrl : wikipediaUrl // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [CatalogBookDetail].
extension CatalogBookDetailPatterns on CatalogBookDetail {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CatalogBookDetail value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CatalogBookDetail() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CatalogBookDetail value)  $default,){
final _that = this;
switch (_that) {
case _CatalogBookDetail():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CatalogBookDetail value)?  $default,){
final _that = this;
switch (_that) {
case _CatalogBookDetail() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? summary,  List<String> subjects,  List<String> bookshelves,  int? fileSize,  String? issued,  String? wikipediaUrl)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CatalogBookDetail() when $default != null:
return $default(_that.summary,_that.subjects,_that.bookshelves,_that.fileSize,_that.issued,_that.wikipediaUrl);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? summary,  List<String> subjects,  List<String> bookshelves,  int? fileSize,  String? issued,  String? wikipediaUrl)  $default,) {final _that = this;
switch (_that) {
case _CatalogBookDetail():
return $default(_that.summary,_that.subjects,_that.bookshelves,_that.fileSize,_that.issued,_that.wikipediaUrl);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? summary,  List<String> subjects,  List<String> bookshelves,  int? fileSize,  String? issued,  String? wikipediaUrl)?  $default,) {final _that = this;
switch (_that) {
case _CatalogBookDetail() when $default != null:
return $default(_that.summary,_that.subjects,_that.bookshelves,_that.fileSize,_that.issued,_that.wikipediaUrl);case _:
  return null;

}
}

}

/// @nodoc


class _CatalogBookDetail implements CatalogBookDetail {
  const _CatalogBookDetail({this.summary,  List<String> subjects = const [],  List<String> bookshelves = const [], this.fileSize, this.issued, this.wikipediaUrl}): _subjects = subjects,_bookshelves = bookshelves;
  

@override final  String? summary;
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

/// Ukuran EPUB dalam byte.
@override final  int? fileSize;
/// Tanggal masuk ke sumber (Gutenberg: tanggal rilis digital, bukan
/// tahun terbit asli). ISO 8601.
@override final  String? issued;
@override final  String? wikipediaUrl;

/// Create a copy of CatalogBookDetail
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CatalogBookDetailCopyWith<_CatalogBookDetail> get copyWith => __$CatalogBookDetailCopyWithImpl<_CatalogBookDetail>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CatalogBookDetail&&(identical(other.summary, summary) || other.summary == summary)&&const DeepCollectionEquality().equals(other.subjects, _subjects)&&const DeepCollectionEquality().equals(other.bookshelves, _bookshelves)&&(identical(other.fileSize, fileSize) || other.fileSize == fileSize)&&(identical(other.issued, issued) || other.issued == issued)&&(identical(other.wikipediaUrl, wikipediaUrl) || other.wikipediaUrl == wikipediaUrl));
}


@override
int get hashCode {
    return Object.hash(runtimeType,summary,const DeepCollectionEquality().hash(_subjects),const DeepCollectionEquality().hash(_bookshelves),fileSize,issued,wikipediaUrl);
}

@override
String toString() {
    return 'CatalogBookDetail(summary: $summary, subjects: $subjects, bookshelves: $bookshelves, fileSize: $fileSize, issued: $issued, wikipediaUrl: $wikipediaUrl)';
}


}

/// @nodoc
abstract mixin class _$CatalogBookDetailCopyWith<$Res> implements $CatalogBookDetailCopyWith<$Res> {
  factory _$CatalogBookDetailCopyWith(_CatalogBookDetail value, $Res Function(_CatalogBookDetail) _then) = __$CatalogBookDetailCopyWithImpl;
@override @useResult
$Res call({
 String? summary, List<String> subjects, List<String> bookshelves, int? fileSize, String? issued, String? wikipediaUrl
});




}
/// @nodoc
class __$CatalogBookDetailCopyWithImpl<$Res>
    implements _$CatalogBookDetailCopyWith<$Res> {
  __$CatalogBookDetailCopyWithImpl(this._self, this._then);

  final _CatalogBookDetail _self;
  final $Res Function(_CatalogBookDetail) _then;

/// Create a copy of CatalogBookDetail
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? summary = freezed,Object? subjects = null,Object? bookshelves = null,Object? fileSize = freezed,Object? issued = freezed,Object? wikipediaUrl = freezed,}) {
  return _then(_CatalogBookDetail(
summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String?,subjects: null == subjects ? _self._subjects : subjects // ignore: cast_nullable_to_non_nullable
as List<String>,bookshelves: null == bookshelves ? _self._bookshelves : bookshelves // ignore: cast_nullable_to_non_nullable
as List<String>,fileSize: freezed == fileSize ? _self.fileSize : fileSize // ignore: cast_nullable_to_non_nullable
as int?,issued: freezed == issued ? _self.issued : issued // ignore: cast_nullable_to_non_nullable
as String?,wikipediaUrl: freezed == wikipediaUrl ? _self.wikipediaUrl : wikipediaUrl // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
