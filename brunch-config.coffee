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
        'zync.js': /^app.shared-object.coffee/
        'unit-test-stubs.js': /^app.unit-test-stubs/
        'vendor.js': /^(vendor|bower_components)/
        'unit-tests.js': /^test.*.spec.coffee|app.pragmas.js/
        'scenarios.js': /^test.*e2e.coffee/
      order:
        before: [
          'app/pragmas.js'
        ]
  plugins:
      uglify:
          mangle: true
