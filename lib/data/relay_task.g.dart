// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'relay_task.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetRelayTaskCollection on Isar {
  IsarCollection<RelayTask> get relayTasks => this.collection();
}

const RelayTaskSchema = CollectionSchema(
  name: r'RelayTask',
  id: 749428253666572245,
  properties: {
    r'createdAt': PropertySchema(
      id: 0,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'data': PropertySchema(id: 1, name: r'data', type: IsarType.longList),
    r'messageId': PropertySchema(
      id: 2,
      name: r'messageId',
      type: IsarType.long,
    ),
    r'originId': PropertySchema(id: 3, name: r'originId', type: IsarType.long),
    r'pendingNeighborIds': PropertySchema(
      id: 4,
      name: r'pendingNeighborIds',
      type: IsarType.longList,
    ),
    r'sentCount': PropertySchema(
      id: 5,
      name: r'sentCount',
      type: IsarType.long,
    ),
    r'targetId': PropertySchema(id: 6, name: r'targetId', type: IsarType.long),
    r'type': PropertySchema(id: 7, name: r'type', type: IsarType.long),
  },

  estimateSize: _relayTaskEstimateSize,
  serialize: _relayTaskSerialize,
  deserialize: _relayTaskDeserialize,
  deserializeProp: _relayTaskDeserializeProp,
  idName: r'id',
  indexes: {
    r'messageId': IndexSchema(
      id: -635287409172016016,
      name: r'messageId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'messageId',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
    r'originId': IndexSchema(
      id: 6997121843849413747,
      name: r'originId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'originId',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
    r'createdAt': IndexSchema(
      id: -3433535483987302584,
      name: r'createdAt',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'createdAt',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _relayTaskGetId,
  getLinks: _relayTaskGetLinks,
  attach: _relayTaskAttach,
  version: '3.3.2',
);

int _relayTaskEstimateSize(
  RelayTask object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.data.length * 8;
  bytesCount += 3 + object.pendingNeighborIds.length * 8;
  return bytesCount;
}

void _relayTaskSerialize(
  RelayTask object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDateTime(offsets[0], object.createdAt);
  writer.writeLongList(offsets[1], object.data);
  writer.writeLong(offsets[2], object.messageId);
  writer.writeLong(offsets[3], object.originId);
  writer.writeLongList(offsets[4], object.pendingNeighborIds);
  writer.writeLong(offsets[5], object.sentCount);
  writer.writeLong(offsets[6], object.targetId);
  writer.writeLong(offsets[7], object.type);
}

RelayTask _relayTaskDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = RelayTask();
  object.createdAt = reader.readDateTime(offsets[0]);
  object.data = reader.readLongList(offsets[1]) ?? [];
  object.id = id;
  object.messageId = reader.readLong(offsets[2]);
  object.originId = reader.readLong(offsets[3]);
  object.pendingNeighborIds = reader.readLongList(offsets[4]) ?? [];
  object.sentCount = reader.readLong(offsets[5]);
  object.targetId = reader.readLong(offsets[6]);
  object.type = reader.readLong(offsets[7]);
  return object;
}

P _relayTaskDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDateTime(offset)) as P;
    case 1:
      return (reader.readLongList(offset) ?? []) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readLong(offset)) as P;
    case 4:
      return (reader.readLongList(offset) ?? []) as P;
    case 5:
      return (reader.readLong(offset)) as P;
    case 6:
      return (reader.readLong(offset)) as P;
    case 7:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _relayTaskGetId(RelayTask object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _relayTaskGetLinks(RelayTask object) {
  return [];
}

void _relayTaskAttach(IsarCollection<dynamic> col, Id id, RelayTask object) {
  object.id = id;
}

extension RelayTaskQueryWhereSort
    on QueryBuilder<RelayTask, RelayTask, QWhere> {
  QueryBuilder<RelayTask, RelayTask, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterWhere> anyMessageId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'messageId'),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterWhere> anyOriginId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'originId'),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterWhere> anyCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'createdAt'),
      );
    });
  }
}

extension RelayTaskQueryWhere
    on QueryBuilder<RelayTask, RelayTask, QWhereClause> {
  QueryBuilder<RelayTask, RelayTask, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterWhereClause> idNotEqualTo(Id id) {
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

  QueryBuilder<RelayTask, RelayTask, QAfterWhereClause> idGreaterThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterWhereClause> idLessThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterWhereClause> idBetween(
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

  QueryBuilder<RelayTask, RelayTask, QAfterWhereClause> messageIdEqualTo(
    int messageId,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'messageId', value: [messageId]),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterWhereClause> messageIdNotEqualTo(
    int messageId,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'messageId',
                lower: [],
                upper: [messageId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'messageId',
                lower: [messageId],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'messageId',
                lower: [messageId],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'messageId',
                lower: [],
                upper: [messageId],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterWhereClause> messageIdGreaterThan(
    int messageId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'messageId',
          lower: [messageId],
          includeLower: include,
          upper: [],
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterWhereClause> messageIdLessThan(
    int messageId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'messageId',
          lower: [],
          upper: [messageId],
          includeUpper: include,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterWhereClause> messageIdBetween(
    int lowerMessageId,
    int upperMessageId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'messageId',
          lower: [lowerMessageId],
          includeLower: includeLower,
          upper: [upperMessageId],
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterWhereClause> originIdEqualTo(
    int originId,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'originId', value: [originId]),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterWhereClause> originIdNotEqualTo(
    int originId,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'originId',
                lower: [],
                upper: [originId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'originId',
                lower: [originId],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'originId',
                lower: [originId],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'originId',
                lower: [],
                upper: [originId],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterWhereClause> originIdGreaterThan(
    int originId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'originId',
          lower: [originId],
          includeLower: include,
          upper: [],
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterWhereClause> originIdLessThan(
    int originId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'originId',
          lower: [],
          upper: [originId],
          includeUpper: include,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterWhereClause> originIdBetween(
    int lowerOriginId,
    int upperOriginId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'originId',
          lower: [lowerOriginId],
          includeLower: includeLower,
          upper: [upperOriginId],
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterWhereClause> createdAtEqualTo(
    DateTime createdAt,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'createdAt', value: [createdAt]),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterWhereClause> createdAtNotEqualTo(
    DateTime createdAt,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'createdAt',
                lower: [],
                upper: [createdAt],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'createdAt',
                lower: [createdAt],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'createdAt',
                lower: [createdAt],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'createdAt',
                lower: [],
                upper: [createdAt],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterWhereClause> createdAtGreaterThan(
    DateTime createdAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'createdAt',
          lower: [createdAt],
          includeLower: include,
          upper: [],
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterWhereClause> createdAtLessThan(
    DateTime createdAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'createdAt',
          lower: [],
          upper: [createdAt],
          includeUpper: include,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterWhereClause> createdAtBetween(
    DateTime lowerCreatedAt,
    DateTime upperCreatedAt, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'createdAt',
          lower: [lowerCreatedAt],
          includeLower: includeLower,
          upper: [upperCreatedAt],
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension RelayTaskQueryFilter
    on QueryBuilder<RelayTask, RelayTask, QFilterCondition> {
  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> createdAtEqualTo(
    DateTime value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'createdAt', value: value),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition>
  createdAtGreaterThan(DateTime value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'createdAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> createdAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'createdAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> createdAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'createdAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> dataElementEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'data', value: value),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition>
  dataElementGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'data',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> dataElementLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'data',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> dataElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'data',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> dataLengthEqualTo(
    int length,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'data', length, true, length, true);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> dataIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'data', 0, true, 0, true);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> dataIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'data', 0, false, 999999, true);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> dataLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'data', 0, true, length, include);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition>
  dataLengthGreaterThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'data', length, include, 999999, true);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> dataLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'data',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> idEqualTo(
    Id value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> idLessThan(
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

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> idBetween(
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

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> messageIdEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'messageId', value: value),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition>
  messageIdGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'messageId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> messageIdLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'messageId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> messageIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'messageId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> originIdEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'originId', value: value),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> originIdGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'originId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> originIdLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'originId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> originIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'originId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition>
  pendingNeighborIdsElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'pendingNeighborIds', value: value),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition>
  pendingNeighborIdsElementGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'pendingNeighborIds',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition>
  pendingNeighborIdsElementLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'pendingNeighborIds',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition>
  pendingNeighborIdsElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'pendingNeighborIds',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition>
  pendingNeighborIdsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'pendingNeighborIds',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition>
  pendingNeighborIdsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'pendingNeighborIds', 0, true, 0, true);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition>
  pendingNeighborIdsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'pendingNeighborIds', 0, false, 999999, true);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition>
  pendingNeighborIdsLengthLessThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'pendingNeighborIds', 0, true, length, include);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition>
  pendingNeighborIdsLengthGreaterThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'pendingNeighborIds',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition>
  pendingNeighborIdsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'pendingNeighborIds',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> sentCountEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'sentCount', value: value),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition>
  sentCountGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'sentCount',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> sentCountLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'sentCount',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> sentCountBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'sentCount',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> targetIdEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'targetId', value: value),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> targetIdGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'targetId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> targetIdLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'targetId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> targetIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'targetId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> typeEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'type', value: value),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> typeGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'type',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> typeLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'type',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterFilterCondition> typeBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'type',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension RelayTaskQueryObject
    on QueryBuilder<RelayTask, RelayTask, QFilterCondition> {}

extension RelayTaskQueryLinks
    on QueryBuilder<RelayTask, RelayTask, QFilterCondition> {}

extension RelayTaskQuerySortBy on QueryBuilder<RelayTask, RelayTask, QSortBy> {
  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> sortByMessageId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'messageId', Sort.asc);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> sortByMessageIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'messageId', Sort.desc);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> sortByOriginId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'originId', Sort.asc);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> sortByOriginIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'originId', Sort.desc);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> sortBySentCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sentCount', Sort.asc);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> sortBySentCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sentCount', Sort.desc);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> sortByTargetId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'targetId', Sort.asc);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> sortByTargetIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'targetId', Sort.desc);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> sortByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.asc);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> sortByTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.desc);
    });
  }
}

extension RelayTaskQuerySortThenBy
    on QueryBuilder<RelayTask, RelayTask, QSortThenBy> {
  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> thenByMessageId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'messageId', Sort.asc);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> thenByMessageIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'messageId', Sort.desc);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> thenByOriginId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'originId', Sort.asc);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> thenByOriginIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'originId', Sort.desc);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> thenBySentCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sentCount', Sort.asc);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> thenBySentCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sentCount', Sort.desc);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> thenByTargetId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'targetId', Sort.asc);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> thenByTargetIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'targetId', Sort.desc);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> thenByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.asc);
    });
  }

  QueryBuilder<RelayTask, RelayTask, QAfterSortBy> thenByTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.desc);
    });
  }
}

extension RelayTaskQueryWhereDistinct
    on QueryBuilder<RelayTask, RelayTask, QDistinct> {
  QueryBuilder<RelayTask, RelayTask, QDistinct> distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<RelayTask, RelayTask, QDistinct> distinctByData() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'data');
    });
  }

  QueryBuilder<RelayTask, RelayTask, QDistinct> distinctByMessageId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'messageId');
    });
  }

  QueryBuilder<RelayTask, RelayTask, QDistinct> distinctByOriginId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'originId');
    });
  }

  QueryBuilder<RelayTask, RelayTask, QDistinct> distinctByPendingNeighborIds() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'pendingNeighborIds');
    });
  }

  QueryBuilder<RelayTask, RelayTask, QDistinct> distinctBySentCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sentCount');
    });
  }

  QueryBuilder<RelayTask, RelayTask, QDistinct> distinctByTargetId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'targetId');
    });
  }

  QueryBuilder<RelayTask, RelayTask, QDistinct> distinctByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'type');
    });
  }
}

extension RelayTaskQueryProperty
    on QueryBuilder<RelayTask, RelayTask, QQueryProperty> {
  QueryBuilder<RelayTask, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<RelayTask, DateTime, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<RelayTask, List<int>, QQueryOperations> dataProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'data');
    });
  }

  QueryBuilder<RelayTask, int, QQueryOperations> messageIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'messageId');
    });
  }

  QueryBuilder<RelayTask, int, QQueryOperations> originIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'originId');
    });
  }

  QueryBuilder<RelayTask, List<int>, QQueryOperations>
  pendingNeighborIdsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'pendingNeighborIds');
    });
  }

  QueryBuilder<RelayTask, int, QQueryOperations> sentCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sentCount');
    });
  }

  QueryBuilder<RelayTask, int, QQueryOperations> targetIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'targetId');
    });
  }

  QueryBuilder<RelayTask, int, QQueryOperations> typeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'type');
    });
  }
}
