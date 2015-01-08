module.exports = (grunt) ->
  # Project configuration.
  grunt.initConfig
    pkg: grunt.file.readJSON('package.json'),
    uglify:
        options:
            banner: '/*! <%= pkg.name %> <%= grunt.template.today("yyyy-mm-dd") %> */\n'
        build:
            src: 'target/so-client.js',
            dest: 'target/so-client.min.js'
    coffee:
        compile:
            options:
                bare: true
            files:
                'target/so-client.js': 'app/*.coffee'

  # Load the plugin that provides the "uglify" task.
  grunt.loadNpmTasks('grunt-contrib-uglify')
  grunt.loadNpmTasks('grunt-contrib-coffee')

  # Default task(s).
  grunt.registerTask('default', 'Do something', ->
    grunt.log.write("Hi!")
  )
