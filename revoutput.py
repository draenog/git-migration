from cvs2svn_lib.context import Ctx
from cvs2svn_lib.symbol import Trunk
from cvs2svn_lib.git_output_option import GitOutputOption

class GitOutputRev(GitOutputOption):

  def __init__(self, dump_filename, revision_writer,
        author_transforms=None,
        tie_tag_fixup_branches=False,
        ):
    GitOutputOption.__init__(self, dump_filename, revision_writer, author_transforms, tie_tag_fixup_branches)
  
  def process_primary_commit(self, svn_commit):
    author = self._get_author(svn_commit)
    log_msg = self._get_log_msg(svn_commit)
    log_msg = log_msg + "\nChanged files:"
    for (cvs_path, rev) in sorted(
        (cvs_rev.cvs_file.cvs_path, cvs_rev.rev) for cvs_rev in svn_commit.get_cvs_items()
        ):
        log_msg = log_msg + "\n    " + cvs_path+ " -> " + rev

    lods = set()
    for cvs_rev in svn_commit.get_cvs_items():
      lods.add(cvs_rev.lod)
    if len(lods) != 1:
      raise InternalError('Commit affects %d LODs' % (len(lods),))
    lod = lods.pop()

    self._mirror.start_commit(svn_commit.revnum)
    if isinstance(lod, Trunk):
      # FIXME: is this correct?:
      self.f.write('commit refs/heads/master\n')
    else:
      self.f.write('commit refs/heads/%s\n' % (lod.name,))
    self.f.write(
        'mark :%d\n'
        % (self._create_commit_mark(lod, svn_commit.revnum),)
        )
    self.f.write(
        'committer %s %d +0000\n' % (author, svn_commit.date,)
        )
    self.f.write('data %d\n' % (len(log_msg),))
    self.f.write('%s\n' % (log_msg,))
    for cvs_rev in svn_commit.get_cvs_items():
      self.revision_writer.process_revision(cvs_rev, post_commit=False)

    self.f.write('\n')
    self._mirror.end_commit()

  def _process_symbol_commit(self, svn_commit, git_branch, source_groups):
    author = self._get_author(svn_commit)
    log_msg = self._get_log_msg(svn_commit)

    # There are two distinct cases we need to care for here:
    #  1. initial creation of a LOD
    #  2. fixup of an existing LOD to include more files, because the LOD in
    #     CVS was created piecemeal over time, with intervening commits

    # We look at _marks here, but self._mirror._get_lod_history(lod).exists()
    # might be technically more correct (though _get_lod_history is currently
    # underscore-private)
    is_initial_lod_creation = svn_commit.symbol not in self._marks

    # Create the mark, only after the check above
    mark = self._create_commit_mark(svn_commit.symbol, svn_commit.revnum)

    if is_initial_lod_creation:
      # Get the primary parent
      p_source_revnum, p_source_lod, p_cvs_symbols = source_groups[0]
      try:
        p_source_node = self._mirror.get_old_lod_directory(
            p_source_lod, p_source_revnum
            )
      except KeyError:
        raise InternalError('Source %r does not exist' % (p_source_lod,))
      cvs_files_to_delete = set(self._get_all_files(p_source_node))

      for (source_revnum, source_lod, cvs_symbols,) in source_groups:
        for cvs_symbol in cvs_symbols:
          cvs_files_to_delete.discard(cvs_symbol.cvs_file)

    # Write a trailer to the log message which describes the cherrypicks that
    # make up this symbol creation.
    log_msg += "\n"
    if is_initial_lod_creation:
      log_msg += "\nSprout from %s" % (
          self._describe_commit(
              Ctx()._persistence_manager.get_svn_commit(p_source_revnum),
              p_source_lod
              ),
          )
    for (source_revnum, source_lod, cvs_symbols,) \
            in source_groups[(is_initial_lod_creation and 1 or 0):]:
      log_msg += "\nCherrypick from %s:" % (
          self._describe_commit(
              Ctx()._persistence_manager.get_svn_commit(source_revnum),
              source_lod
              ),
          )
      rev = {}
      for cvs_symbol in cvs_symbols:
          cvs_file = cvs_symbol.get_cvs_revision_source(Ctx()._cvs_items_db)
          rev[cvs_file.cvs_path] = cvs_file.rev
      for cvs_path in sorted(rev.iterkeys()):
        log_msg += "\n    %s -> %s" % (cvs_path, rev[cvs_path])
    if is_initial_lod_creation:
      if cvs_files_to_delete:
        log_msg += "\nDelete:"
        for cvs_path in sorted(
              cvs_file.cvs_path for cvs_file in cvs_files_to_delete
              ):
          log_msg += "\n    %s" % (cvs_path,)

    self.f.write('commit %s\n' % (git_branch,))
    self.f.write('mark :%d\n' % (mark,))
    self.f.write('committer %s %d +0000\n' % (author, svn_commit.date,))
    self.f.write('data %d\n' % (len(log_msg),))
    self.f.write('%s\n' % (log_msg,))

    # Only record actual DVCS ancestry for the primary sprout parent,
    # all the rest are effectively cherrypicks.
    if is_initial_lod_creation:
      self.f.write(
          'from :%d\n'
          % (self._get_source_mark(p_source_lod, p_source_revnum),)
          )

    for (source_revnum, source_lod, cvs_symbols,) in source_groups:
      for cvs_symbol in cvs_symbols:
        self.revision_writer.branch_file(cvs_symbol)

    if is_initial_lod_creation:
      for cvs_file in cvs_files_to_delete:
        self.f.write('D %s\n' % (cvs_file.cvs_path,))

    self.f.write('\n')
    return mark

