return {
  'nvim-orgmode/orgmode',
  opts = {
    org_agenda_files = '~/org/*',
    org_adapt_indentation = false,
    org_startup_folded = 'showeverything',
    mappings = {
      global = {
        org_agenda = '<F2>a',
        org_capture = '<F2>c',
      },
      org = {
        org_timestamp_up = false,
        org_timestamp_down = false,
      }
    },
  }
}
