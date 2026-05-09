// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'found_device.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetFoundDeviceCollection on Isar {
  IsarCollection<FoundDevice> get foundDevices => this.collection();
}

const FoundDeviceSchema = CollectionSchema(
  name: r'FoundDevice',
  id: -210013710228081359,
  properties: {
    r'lastSeen': PropertySchema(
      id: 0,
      name: r'lastSeen',
      type: IsarType.dateTime,
    ),
    r'name': PropertySchema(id: 1, name: r'name', type: IsarType.string),
    r'profileHash': PropertySchema(
      id: 2,
      name: r'profileHash',
      type: IsarType.string,
    ),
    r'profilePicture': PropertySchema(
      id: 3,
      name: r'profilePicture',
      type: IsarType.longList,
    ),
    r'remoteId': PropertySchema(
      id: 4,
      name: r'remoteId',
      type: IsarType.string,
    ),
    r'rssi': PropertySchema(id: 5, name: r'rssi', type: IsarType.long),
  },

  estimateSize: _foundDeviceEstimateSize,
  serialize: _foundDeviceSerialize,
  deserialize: _foundDeviceDeserialize,
  deserializeProp: _foundDeviceDeserializeProp,
  idName: r'id',
  indexes: {
    r'remoteId': IndexSchema(
      id: 6301175856541681032,
      name: r'remoteId',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'remoteId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'profileHash': IndexSchema(
      id: 4173175201119785314,
      name: r'profileHash',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'profileHash',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _foundDeviceGetId,
  getLinks: _foundDeviceGetLinks,
  attach: _foundDeviceAttach,
  version: '3.3.2',
);

int _foundDeviceEstimateSize(
  FoundDevice object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.name;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.profileHash;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.profilePicture;
    if (value != null) {
      bytesCount += 3 + value.length * 8;
    }
  }
  bytesCount += 3 + object.remoteId.length * 3;
  return bytesCount;
}

void _foundDeviceSerialize(
  FoundDevice object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDateTime(offsets[0], object.lastSeen);
  writer.writeString(offsets[1], object.name);
  writer.writeString(offsets[2], object.profileHash);
  writer.writeLongList(offsets[3], object.profilePicture);
  writer.writeString(offsets[4], object.remoteId);
  writer.writeLong(offsets[5], object.rssi);
}

FoundDevice _foundDeviceDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = FoundDevice();
  object.id = id;
  object.lastSeen = reader.readDateTime(offsets[0]);
  object.name = reader.readStringOrNull(offsets[1]);
  object.profileHash = reader.readStringOrNull(offsets[2]);
  object.profilePicture = reader.readLongList(offsets[3]);
  object.remoteId = reader.readString(offsets[4]);
  object.rssi = reader.readLong(offsets[5]);
  return object;
}

P _foundDeviceDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDateTime(offset)) as P;
    case 1:
      return (reader.readStringOrNull(offset)) as P;
    case 2:
      return (reader.readStringOrNull(offset)) as P;
    case 3:
      return (reader.readLongList(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _foundDeviceGetId(FoundDevice object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _foundDeviceGetLinks(FoundDevice object) {
  return [];
}

void _foundDeviceAttach(
  IsarCollection<dynamic> col,
  Id id,
  FoundDevice object,
) {
  object.id = id;
}

extension FoundDeviceByIndex on IsarCollection<FoundDevice> {
  Future<FoundDevice?> getByRemoteId(String remoteId) {
    return getByIndex(r'remoteId', [remoteId]);
  }

  FoundDevice? getByRemoteIdSync(String remoteId) {
    return getByIndexSync(r'remoteId', [remoteId]);
  }

  Future<bool> deleteByRemoteId(String remoteId) {
    return deleteByIndex(r'remoteId', [remoteId]);
  }

  bool deleteByRemoteIdSync(String remoteId) {
    return deleteByIndexSync(r'remoteId', [remoteId]);
  }

  Future<List<FoundDevice?>> getAllByRemoteId(List<String> remoteIdValues) {
    final values = remoteIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'remoteId', values);
  }

  List<FoundDevice?> getAllByRemoteIdSync(List<String> remoteIdValues) {
    final values = remoteIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'remoteId', values);
  }

  Future<int> deleteAllByRemoteId(List<String> remoteIdValues) {
    final values = remoteIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'remoteId', values);
  }

  int deleteAllByRemoteIdSync(List<String> remoteIdValues) {
    final values = remoteIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'remoteId', values);
  }

  Future<Id> putByRemoteId(FoundDevice object) {
    return putByIndex(r'remoteId', object);
  }

  Id putByRemoteIdSync(FoundDevice object, {bool saveLinks = true}) {
    return putByIndexSync(r'remoteId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByRemoteId(List<FoundDevice> objects) {
    return putAllByIndex(r'remoteId', objects);
  }

  List<Id> putAllByRemoteIdSync(
    List<FoundDevice> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(r'remoteId', objects, saveLinks: saveLinks);
  }
}

extension FoundDeviceQueryWhereSort
    on QueryBuilder<FoundDevice, FoundDevice, QWhere> {
  QueryBuilder<FoundDevice, FoundDevice, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension FoundDeviceQueryWhere
    on QueryBuilder<FoundDevice, FoundDevice, QWhereClause> {
  QueryBuilder<FoundDevice, FoundDevice, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterWhereClause> idNotEqualTo(
    Id id,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterWhereClause> idGreaterThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterWhereClause> idLessThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(
          lower: lowerId,
          includeLower: includeLower,
          upper: upperId,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterWhereClause> remoteIdEqualTo(
    String remoteId,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'remoteId', value: [remoteId]),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterWhereClause> remoteIdNotEqualTo(
    String remoteId,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'remoteId',
                lower: [],
                upper: [remoteId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'remoteId',
                lower: [remoteId],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'remoteId',
                lower: [remoteId],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'remoteId',
                lower: [],
                upper: [remoteId],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterWhereClause>
  profileHashIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'profileHash', value: [null]),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterWhereClause>
  profileHashIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'profileHash',
          lower: [null],
          includeLower: false,
          upper: [],
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterWhereClause> profileHashEqualTo(
    String? profileHash,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'profileHash',
          value: [profileHash],
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterWhereClause>
  profileHashNotEqualTo(String? profileHash) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'profileHash',
                lower: [],
                upper: [profileHash],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'profileHash',
                lower: [profileHash],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'profileHash',
                lower: [profileHash],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'profileHash',
                lower: [],
                upper: [profileHash],
                includeUpper: false,
              ),
            );
      }
    });
  }
}

extension FoundDeviceQueryFilter
    on QueryBuilder<FoundDevice, FoundDevice, QFilterCondition> {
  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition> idEqualTo(
    Id value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'id',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition> lastSeenEqualTo(
    DateTime value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'lastSeen', value: value),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  lastSeenGreaterThan(DateTime value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lastSeen',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  lastSeenLessThan(DateTime value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lastSeen',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition> lastSeenBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lastSeen',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition> nameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'name'),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  nameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'name'),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition> nameEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition> nameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition> nameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition> nameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'name',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition> nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition> nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition> nameContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition> nameMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'name',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition> nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'name', value: ''),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'name', value: ''),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  profileHashIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'profileHash'),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  profileHashIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'profileHash'),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  profileHashEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'profileHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  profileHashGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'profileHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  profileHashLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'profileHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  profileHashBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'profileHash',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  profileHashStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'profileHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  profileHashEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'profileHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  profileHashContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'profileHash',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  profileHashMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'profileHash',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  profileHashIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'profileHash', value: ''),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  profileHashIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'profileHash', value: ''),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  profilePictureIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'profilePicture'),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  profilePictureIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'profilePicture'),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  profilePictureElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'profilePicture', value: value),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  profilePictureElementGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'profilePicture',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  profilePictureElementLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'profilePicture',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  profilePictureElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'profilePicture',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  profilePictureLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'profilePicture', length, true, length, true);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  profilePictureIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'profilePicture', 0, true, 0, true);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  profilePictureIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'profilePicture', 0, false, 999999, true);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  profilePictureLengthLessThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'profilePicture', 0, true, length, include);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  profilePictureLengthGreaterThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'profilePicture', length, include, 999999, true);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  profilePictureLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'profilePicture',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition> remoteIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'remoteId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  remoteIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'remoteId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  remoteIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'remoteId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition> remoteIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'remoteId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  remoteIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'remoteId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  remoteIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'remoteId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  remoteIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'remoteId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition> remoteIdMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'remoteId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  remoteIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'remoteId', value: ''),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition>
  remoteIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'remoteId', value: ''),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition> rssiEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'rssi', value: value),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition> rssiGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'rssi',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition> rssiLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'rssi',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterFilterCondition> rssiBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'rssi',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension FoundDeviceQueryObject
    on QueryBuilder<FoundDevice, FoundDevice, QFilterCondition> {}

extension FoundDeviceQueryLinks
    on QueryBuilder<FoundDevice, FoundDevice, QFilterCondition> {}

extension FoundDeviceQuerySortBy
    on QueryBuilder<FoundDevice, FoundDevice, QSortBy> {
  QueryBuilder<FoundDevice, FoundDevice, QAfterSortBy> sortByLastSeen() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSeen', Sort.asc);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterSortBy> sortByLastSeenDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSeen', Sort.desc);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterSortBy> sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterSortBy> sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterSortBy> sortByProfileHash() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileHash', Sort.asc);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterSortBy> sortByProfileHashDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileHash', Sort.desc);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterSortBy> sortByRemoteId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'remoteId', Sort.asc);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterSortBy> sortByRemoteIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'remoteId', Sort.desc);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterSortBy> sortByRssi() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rssi', Sort.asc);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterSortBy> sortByRssiDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rssi', Sort.desc);
    });
  }
}

extension FoundDeviceQuerySortThenBy
    on QueryBuilder<FoundDevice, FoundDevice, QSortThenBy> {
  QueryBuilder<FoundDevice, FoundDevice, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterSortBy> thenByLastSeen() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSeen', Sort.asc);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterSortBy> thenByLastSeenDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSeen', Sort.desc);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterSortBy> thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterSortBy> thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterSortBy> thenByProfileHash() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileHash', Sort.asc);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterSortBy> thenByProfileHashDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileHash', Sort.desc);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterSortBy> thenByRemoteId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'remoteId', Sort.asc);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterSortBy> thenByRemoteIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'remoteId', Sort.desc);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterSortBy> thenByRssi() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rssi', Sort.asc);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QAfterSortBy> thenByRssiDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rssi', Sort.desc);
    });
  }
}

extension FoundDeviceQueryWhereDistinct
    on QueryBuilder<FoundDevice, FoundDevice, QDistinct> {
  QueryBuilder<FoundDevice, FoundDevice, QDistinct> distinctByLastSeen() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastSeen');
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QDistinct> distinctByName({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QDistinct> distinctByProfileHash({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'profileHash', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QDistinct> distinctByProfilePicture() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'profilePicture');
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QDistinct> distinctByRemoteId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'remoteId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FoundDevice, FoundDevice, QDistinct> distinctByRssi() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'rssi');
    });
  }
}

extension FoundDeviceQueryProperty
    on QueryBuilder<FoundDevice, FoundDevice, QQueryProperty> {
  QueryBuilder<FoundDevice, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<FoundDevice, DateTime, QQueryOperations> lastSeenProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastSeen');
    });
  }

  QueryBuilder<FoundDevice, String?, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<FoundDevice, String?, QQueryOperations> profileHashProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'profileHash');
    });
  }

  QueryBuilder<FoundDevice, List<int>?, QQueryOperations>
  profilePictureProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'profilePicture');
    });
  }

  QueryBuilder<FoundDevice, String, QQueryOperations> remoteIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'remoteId');
    });
  }

  QueryBuilder<FoundDevice, int, QQueryOperations> rssiProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'rssi');
    });
  }
}
