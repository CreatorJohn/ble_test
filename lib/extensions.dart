extension StringExtension on String {
  String title() => split(" ")
      .map((it) {
        if (it.isEmpty) {
          return "";
        } else if (it.length == 1) {
          return it.toUpperCase();
        }

        final first = it[0].toUpperCase();
        final rest = it.substring(1).toLowerCase();

        return first + rest;
      })
      .join(" ");
}
