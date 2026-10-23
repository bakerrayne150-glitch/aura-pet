/// Core Tamagotchi model.
///
/// Stats are 0–100. Decay is computed from wall-clock time, so the pet
/// keeps living while the app is closed — no background service needed.
enum PetMood { content, hungry, bored, tired, grumpy }

extension PetMoodLabel on PetMood {
  String get label => switch (this) {
        PetMood.content => 'Content',
        PetMood.hungry => 'Hungry',
        PetMood.bored => 'Bored',
        PetMood.tired => 'Tired',
        PetMood.grumpy => 'Grumpy',
      };
}

/// Growth stages. Baby (days 0-1), teen (days 2-6), adult (day 7+).
/// Adult lands right as the 7-day trial ends — a fully-grown pet for
/// a fully-unlocked human.
enum LifeStage { baby, teen, adult }

extension LifeStageLabel on LifeStage {
  String get label => switch (this) {
        LifeStage.baby => 'Baby',
        LifeStage.teen => 'Teen',
        LifeStage.adult => 'Adult',
      };
}

class Pet {
  String name;
  double hunger;
  double happiness;
  double energy;
  bool sleeping;
  DateTime lastUpdated;
  DateTime lastPetted;

  /// When this pet hatched — drives the life stage.
  DateTime bornAt;

  /// Last stage the app announced. Persisted so an evolution that
  /// happens while the app is closed still gets its party on return.
  LifeStage lastStage;

  Pet({
    required this.name,
    required this.hunger,
    required this.happiness,
    required this.energy,
    required this.sleeping,
    required this.lastUpdated,
    required this.lastPetted,
    required this.bornAt,
    required this.lastStage,
  });

  factory Pet.fresh(String name) {
    final now = DateTime.now();
    return Pet(
      name: name.isEmpty ? 'Aura' : name,
      hunger: 80,
      happiness: 80,
      energy: 90,
      sleeping: false,
      lastUpdated: now,
      lastPetted: now,
      bornAt: now,
      lastStage: LifeStage.baby,
    );
  }

  /// Age-based growth: baby for the first 2 days, teen until day 7,
  /// adult from day 7 on. Wall-clock, like the stat decay.
  LifeStage get lifeStage {
    final days = DateTime.now().difference(bornAt).inDays;
    if (days < 2) return LifeStage.baby;
    if (days < 7) return LifeStage.teen;
    return LifeStage.adult;
  }

  /// Whole days since hatching — for the chat personality.
  int get ageDays => DateTime.now().difference(bornAt).inDays;

  /// The neediest stat wins; mild neglect reads as grumpy.
  /// The grumpy band is deliberately narrow (~35) so good care visibly
  /// pays off instead of feeling punishing.
  PetMood get mood {
    if (hunger < 25) return PetMood.hungry;
    if (energy < 25) return PetMood.tired;
    if (happiness < 25) return PetMood.bored;
    if (hunger < 35 || happiness < 35 || energy < 35) return PetMood.grumpy;
    return PetMood.content;
  }

  static double _c(double v) => v.clamp(0.0, 100.0).toDouble();

  /// Apply real-time decay. Sleeping slows need-decay and restores energy.
  void applyDecay(DateTime now) {
    final minutes = now.difference(lastUpdated).inMinutes;
    if (minutes <= 0) return;
    final hours = minutes / 60.0;
    final awakeHours = sleeping ? hours * 0.15 : hours;
    hunger = _c(hunger - awakeHours * (100 / 8)); // empty in ~8h
    happiness = _c(happiness - awakeHours * (100 / 6)); // bored in ~6h
    energy = sleeping
        ? _c(energy + hours * (100 / 8)) // full rest in ~8h
        : _c(energy - awakeHours * (100 / 16)); // tired in ~16h
    lastUpdated = now;
  }

  void feed() => hunger = _c(hunger + 35);

  void play() {
    happiness = _c(happiness + 40);
    hunger = _c(hunger - 5);
    energy = _c(energy - 8);
  }

  void pet() {
    happiness = _c(happiness + 5);
    lastPetted = DateTime.now();
  }

  void toggleSleep() => sleeping = !sleeping;

  Map<String, dynamic> toJson() => {
        'name': name,
        'hunger': hunger,
        'happiness': happiness,
        'energy': energy,
        'sleeping': sleeping,
        'lastUpdated': lastUpdated.toIso8601String(),
        'lastPetted': lastPetted.toIso8601String(),
        'bornAt': bornAt.toIso8601String(),
        'lastStage': lastStage.name,
      };

  factory Pet.fromJson(Map<String, dynamic> json) {
    final pet = Pet(
      name: json['name'] as String? ?? 'Aura',
      hunger: (json['hunger'] as num? ?? 80).toDouble(),
      happiness: (json['happiness'] as num? ?? 80).toDouble(),
      energy: (json['energy'] as num? ?? 90).toDouble(),
      sleeping: json['sleeping'] as bool? ?? false,
      lastUpdated:
          DateTime.tryParse(json['lastUpdated'] as String? ?? '') ??
              DateTime.now(),
      lastPetted:
          DateTime.tryParse(json['lastPetted'] as String? ?? '') ??
              DateTime.now(),
      bornAt: DateTime.tryParse(json['bornAt'] as String? ?? '') ??
          DateTime.tryParse(json['lastUpdated'] as String? ?? '') ??
              DateTime.now(),
      lastStage: LifeStage.baby, // replaced below
    );
    // Old saves have no stage fields: adopt the current stage so we
    // don't throw a bogus evolution party for a years-old pet.
    final stored = json['lastStage'] as String?;
    pet.lastStage = stored != null
        ? LifeStage.values.firstWhere(
            (s) => s.name == stored,
            orElse: () => pet.lifeStage,
          )
        : pet.lifeStage;
    return pet;
  }
}
