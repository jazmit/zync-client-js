exports.config =
  modules:
      definition: false
      wrapper: false
  paths:
      public: 'target'
      watched: ['app', 'test', 'vendor']
  # See docs at http://brunch.readthedocs.org/en/latest/config.html.
  files:
    javascripts:
      defaultExtension: 'coffee'
      joinTo:
        # Files that change on every deploy
        'so-client.js': /^app/
        # Files that may stay constant between deploys
        'vendor.js': /^(vendor|bower_components)/
        # Unit tests
        'unit-tests.js': /^test.*.spec.coffee|app.pragmas.js/
        # FUTURE: integration tests
        'scenarios.js': /^test.*e2e.coffee/
      order:
        before: [
          'app/pragmas.js'
        ]
  plugins:
      uglify:
          mangle: true
