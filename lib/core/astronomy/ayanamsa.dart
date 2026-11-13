double thaiAyanamsa(DateTime instant) => 23.8523 + 0.013969 *
    ((instant.millisecondsSinceEpoch / 1000 - 946684800) / 31556952.0);

enum ZodiacSystem { thaiSidereal, tropical }
