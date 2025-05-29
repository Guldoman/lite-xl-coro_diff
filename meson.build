project('coro_diff', 'c',
  version: '0.1.2',
  default_options: ['warning_level=3']
)

cc = meson.get_compiler('c')
libm = cc.find_library('m')


shared_library('myers_midpoint',
  ['native/myers_midpoint.c'],
  name_prefix: '',
  dependencies: [libm],
  include_directories: include_directories('native/lite-xl/resources/include/')
)

lua = find_program('lua', required: false)

tests_dir = meson.current_source_dir() + '/tests'

if lua.found()
  test('test', lua,
    env: {
      'LUA_PATH': meson.current_source_dir() + '/library/?.lua',
      'LUA_CPATH': meson.current_build_dir() + '/?.so'
    },
    args: [tests_dir + '/test.lua'],
    protocol: 'tap',
  )
endif
