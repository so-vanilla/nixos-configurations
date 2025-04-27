return {
  'nvim-orgmode/orgmode',
  cmd = { 'Org' },
  ft = { 'org' },
  opts = {
    org_agenda_files = '~/org/*',
    org_adapt_indentation = false,
    mappings = {
      disable_all = true,
    },
  }
}
