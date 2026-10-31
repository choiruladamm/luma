// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalog_row.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_CatalogAuthor _$CatalogAuthorFromJson(Map<String, dynamic> json) =>
    _CatalogAuthor(
      json['name'] as String,
      birth: (json['birth'] as num?)?.toInt(),
      death: (json['death'] as num?)?.toInt(),
    );

Map<String, dynamic> _$CatalogAuthorToJson(_CatalogAuthor instance) =>
    <String, dynamic>{
      'name': instance.name,
      'birth': instance.birth,
      'death': instance.death,
    };
