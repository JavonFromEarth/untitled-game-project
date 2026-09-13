import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_event.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_log.dart';

enum MemberJoinMethod {
  standardRecruitment('standard_recruitment'),
  datingRecruitment('dating_recruitment'),
  siteRescue('site_rescue'),
  hostageConversion('hostage_conversion'),
  releasedHostageSleeper('released_hostage_sleeper'),
  sleeperRecruitment('sleeper_recruitment'),
  campaignOrigin('campaign_origin');

  const MemberJoinMethod(this.wireName);
  final String wireName;
}

/// Only membership resolvers call this, after membership and role are resolved.
void recordMemberJoined({
  required Creature member,
  required Creature recruiter,
  required MemberJoinMethod method,
  Map<String, dynamic> provenance = const {},
}) {
  logPlaythroughEvent(
    gameDate: date,
    type: PlaythroughEventType.memberJoined,
    data: {
      'memberId': member.id,
      'memberName': member.name,
      'memberTypeId': member.typeId,
      'memberTypeName': member.type.name,
      'joinMethod': method.wireName,
      'initialRole': member.sleeperAgent ? 'sleeper' : 'active',
      'recruiterId': recruiter.id,
      'recruiterName': recruiter.name,
      if (provenance.isNotEmpty)
        'provenance': jsonDecode(jsonEncode(provenance)),
    },
  );
}

/// Contact creation is distinct from a completed date or romantic relationship.
void recordDatingContact({
  required Creature actor,
  required Creature person,
  Map<String, dynamic>? sourceSite,
}) {
  logPlaythroughEvent(
    gameDate: date,
    type: PlaythroughEventType.datingContactEstablished,
    data: {
      'actorId': actor.id,
      'actorName': actor.name,
      'personId': person.id,
      'personName': person.name,
      'personTypeId': person.typeId,
      'personTypeName': person.type.name,
      'contactKind': person.typeId == CreatureTypeIds.sexWorker
          ? 'paid_companionship'
          : 'dating',
      if (sourceSite != null) 'sourceSite': jsonDecode(jsonEncode(sourceSite)),
    },
  );
}

Map<String, dynamic> datingJoinProvenance(Creature member, Creature recruiter) {
  // Stable entity IDs identify the pair even after renaming or save/load.
  // Old prospects without recorded contact history deliberately have no link.
  final contact = gameState.playthroughEvents.reversed.firstWhereOrNull(
    (event) =>
        event.gameId == gameState.uniqueGameId &&
        event.type == PlaythroughEventType.datingContactEstablished &&
        event.data['personId'] == member.id &&
        event.data['actorId'] == recruiter.id,
  );
  return {
    'relationshipKind': member.typeId == CreatureTypeIds.sexWorker
        ? 'commercial'
        : 'romantic',
    if (contact != null) 'contactEventSequence': contact.sequence,
  };
}

/// Capture the actual source site before relocation, never infer it from work.
Map<String, dynamic>? historySiteSnapshot(Site? site) {
  if (site == null) return null;
  final city = cities.firstWhereOrNull((city) => city.id == site.cityId);
  if (city == null) return null;
  return {
    'siteId': site.id,
    'siteName': site.name,
    'siteType': _siteTypeWireName(site.type),
    'cityId': city.id,
    'cityName': city.name,
  };
}

// Explicit history contract, separate from SiteType's display-name property.
String _siteTypeWireName(SiteType type) => switch (type) {
  SiteType.clinic => 'clinic',
  SiteType.universityHospital => 'university_hospital',
  SiteType.pawnShop => 'pawn_shop',
  SiteType.departmentStore => 'department_store',
  SiteType.oubliette => 'oubliette',
  SiteType.armsDealer => 'arms_dealer',
  SiteType.carDealership => 'car_dealership',
  SiteType.homelessEncampment => 'homeless_encampment',
  SiteType.tenement => 'tenement',
  SiteType.apartment => 'apartment',
  SiteType.upscaleApartment => 'upscale_apartment',
  SiteType.bombShelter => 'bomb_shelter',
  SiteType.cosmeticsLab => 'cosmetics_lab',
  SiteType.geneticsLab => 'genetics_lab',
  SiteType.policeStation => 'police_station',
  SiteType.courthouse => 'courthouse',
  SiteType.prison => 'prison',
  SiteType.intelligenceHQ => 'intelligence_hq',
  SiteType.fireStation => 'fire_station',
  SiteType.sweatshop => 'sweatshop',
  SiteType.dirtyIndustry => 'dirty_industry',
  SiteType.nuclearPlant => 'nuclear_plant',
  SiteType.warehouse => 'warehouse',
  SiteType.corporateHQ => 'corporate_hq',
  SiteType.ceoHouse => 'ceo_house',
  SiteType.amRadioStation => 'am_radio_station',
  SiteType.cableNewsStation => 'cable_news_station',
  SiteType.drugHouse => 'drug_house',
  SiteType.juiceBar => 'juice_bar',
  SiteType.latteStand => 'latte_stand',
  SiteType.veganCoOp => 'vegan_co_op',
  SiteType.internetCafe => 'internet_cafe',
  SiteType.barAndGrill => 'bar_and_grill',
  SiteType.publicPark => 'public_park',
  SiteType.bunker => 'bunker',
  SiteType.armyBase => 'army_base',
  SiteType.bank => 'bank',
  SiteType.insuranceOffice => 'insurance_office',
  SiteType.nursingHome => 'nursing_home',
  SiteType.liberalPartyHQ => 'liberal_party_hq',
  SiteType.whiteHouse => 'white_house',
  SiteType.downtown => 'downtown',
  SiteType.commercialDistrict => 'commercial_district',
  SiteType.universityDistrict => 'university_district',
  SiteType.industrialDistrict => 'industrial_district',
  SiteType.outOfTown => 'out_of_town',
};
