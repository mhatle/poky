python read_subpackage_metadata () {
    import oe.packagedata

    vars = {
        "PN" : d.getVar('PN'), 
        "PE" : d.getVar('PE'), 
        "PV" : d.getVar('PV'),
        "PR" : d.getVar('PR'),
    }

    data = oe.packagedata.read_pkgdata(vars["PN"], d)

    for key in data.keys():
        d.setVar(key, data[key])

    for pkg in d.getVar('PACKAGES').split():
        sdata = oe.packagedata.read_subpkgdata(pkg, d)
        for key in sdata.keys():
            if key in vars:
                if sdata[key] != vars[key]:
                    if key == "PN":
                        bb.fatal("Recipe %s is trying to create package %s which was already written by recipe %s. This will cause corruption, please resolve this and only provide the package from one recipe or the other or only build one of the recipes." % (vars[key], pkg, sdata[key]))
                    bb.fatal("Recipe %s is trying to change %s from '%s' to '%s'. This will cause do_package_write_* failures since the incorrect data will be used and they will be unable to find the right workdir." % (vars["PN"], key, vars[key], sdata[key]))
                continue
            #
            # If we set unsuffixed variables here there is a chance they could clobber override versions
            # of that variable, e.g. DESCRIPTION could clobber DESCRIPTION_<pkgname>
            # We therefore don't clobber for the unsuffixed variable versions
            #
            if key.endswith("_" + pkg):
                d.setVar(key, sdata[key])
            else:
                d.setVar(key, sdata[key], parsing=True)
}

package_get_auto_pr[vardepsexclude] = "BB_TASKDEPDATA"
python package_get_auto_pr() {
    import oe.prservice

    def get_do_package_hash(pn):
        if d.getVar("BB_RUNTASK") != "do_package":
            taskdepdata = d.getVar("BB_TASKDEPDATA", False)
            for dep in taskdepdata:
                if taskdepdata[dep][1] == "do_package" and taskdepdata[dep][0] == pn:
                    return taskdepdata[dep][6]
        return None

    # Support per recipe PRSERV_HOST
    pn = d.getVar('PN')
    host = d.getVar("PRSERV_HOST_" + pn)
    if not (host is None):
        d.setVar("PRSERV_HOST", host)

    pkgv = d.getVar("PKGV")

    # PR Server not active, handle AUTOINC
    if not d.getVar('PRSERV_HOST'):
        d.setVar("PRSERV_PV_AUTOINC", "0")
        return

    auto_pr = None
    pv = d.getVar("PV")
    version = d.getVar("PRAUTOINX")
    pkgarch = d.getVar("PACKAGE_ARCH")
    checksum = get_do_package_hash(pn)

    # If do_package isn't in the dependencies, we can't get the checksum...
    if not checksum:
        bb.warn('Task %s requested do_package unihash, but it was not available.' % d.getVar('BB_RUNTASK'))
        #taskdepdata = d.getVar("BB_TASKDEPDATA", False)
        #for dep in taskdepdata:
        #    bb.warn('%s:%s = %s' % (taskdepdata[dep][0], taskdepdata[dep][1], taskdepdata[dep][6]))
        return

    if d.getVar('PRSERV_LOCKDOWN'):
        auto_pr = d.getVar('PRAUTO_' + version + '_' + pkgarch) or d.getVar('PRAUTO_' + version) or None
        if auto_pr is None:
            bb.fatal("Can NOT get PRAUTO from lockdown exported file")
        d.setVar('PRAUTO',str(auto_pr))
        return

    try:
        conn = d.getVar("__PRSERV_CONN")
        if conn is None:
            conn = oe.prservice.prserv_make_conn(d)
        if conn is not None:
            if "AUTOINC" in pkgv:
                srcpv = bb.fetch2.get_srcrev(d)
                base_ver = "AUTOINC-%s" % version[:version.find(srcpv)]
                value = conn.getPR(base_ver, pkgarch, srcpv)
                d.setVar("PRSERV_PV_AUTOINC", str(value))

            auto_pr = conn.getPR(version, pkgarch, checksum)
    except Exception as e:
        bb.fatal("Can NOT get PRAUTO, exception %s" %  str(e))
    if auto_pr is None:
        bb.fatal("Can NOT get PRAUTO from remote PR service")
    d.setVar('PRAUTO',str(auto_pr))
}
