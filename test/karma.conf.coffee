module.exports = (config) ->
  config.set
    autoWatch: true
    browsers: ['PhantomJS']
    basePath: '../'
    frameworks: ['jasmine', 'source-map-support']
    files: [
      'target/vendor.js',
      'target/so-client.js',
      'target/unit-tests.js'
    ]
    preprocessors:
        '**/*.coffee': 'coffee',

