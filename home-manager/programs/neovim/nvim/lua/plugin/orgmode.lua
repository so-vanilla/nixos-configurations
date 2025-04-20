return {
  'nvim-orgmode/orgmode',
  event = 'VeryLazy',
  commands = { 'Org' },
  ft = { 'org' },
  opts = {
    org_agenda_files = '~/org/*'
  }
}
