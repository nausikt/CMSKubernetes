import os, socket
from WMCore.Configuration import Configuration

class Config(Configuration):
  """Default T0WmaDataSvc server configuration."""
  def __init__(self, db = None, authkey = None, nthreads = 5, port = 8308):
    """
    :arg str db: Location of database configuration, "module.object". Defaults
      to "t0auth.dbparam".
    :arg str authkey: Location of wmcore security header authentication key.
    :arg integer nthreads: Number of server threads to create.
    :arg integer port: Server port."""

    Configuration.__init__(self)
    main = self.section_('main')
    srv = main.section_('server')
    srv.thread_pool = nthreads
    main.application = 't0wmadatasvc'
    main.port = port
    main.index = 'data'

    main.authz_defaults = { 'role': None, 'group': None, 'site': None }
    sec = main.section_('tools').section_("cms_auth")
    sec.key_file = authkey

    app = self.section_('t0wmadatasvc')
    app.admin = 'cms-service-cmsprod@cern.ch'
    app.description = 'Access to the CMS Tier0 database'
    app.title = 'CMS T0 WMAgent Data Service'

    views = self.section_('views')
    data = views.section_('data')
    data.object = 'T0WmaDataSvc.Data.Data'
    data.db = db or 't0auth.dbparam'
    

os.environ["NLS_LANG"] = ".AL32UTF8"

THREADS = 10
HOST = socket.gethostname().lower()
KEY_FILE = "%s/auth/wmcore-auth/header-auth-key" % __file__.rsplit('/', 3)[0]
config = Config(nthreads = THREADS, authkey = KEY_FILE)

config.main.tools.cms_auth.policy = 'dangerously_insecure'
config.main.server.environment = 'staging'
config.main.server.socket_host = '127.0.0.1'
