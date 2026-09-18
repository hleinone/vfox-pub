PLUGIN = {
    name = "pub",
    version = "0.1.0",
    description = "mise backend plugin for Dart pub packages",
    author = "hleinone",
    homepage = "https://github.com/hleinone/vfox-pub",
    license = "MIT",
    -- mise puts these tools on PATH during install when the user manages them with mise.
    depends = { "dart", "flutter" },
    notes = { "Requires the dart executable on PATH at install time and at run time." },
}
