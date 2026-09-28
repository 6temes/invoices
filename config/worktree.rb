require "digest"

# A linked git worktree (its `.git` is a file) gets a port and database names derived from its
# checkout path, so several checkouts can run at once; the main checkout keeps the defaults.
# The herdr worktree-setup plugin derives the same identity, so the formula must stay in step.
module Worktree
  module_function

  def database_name(base, root)
    hash8 = identity(root)
    hash8 ? "#{base}_wt_#{hash8}" : base
  end

  def identity(root)
    Digest::SHA256.hexdigest(File.realpath(root))[0, 8] if File.file?(File.join(root, ".git"))
  end

  # 3100 to 3899 never meets 3000, 3001 or the tunnel ports.
  def port(root, default)
    hash8 = identity(root)
    hash8 ? 3100 + (hash8.to_i(16) % 800) : default
  end
end
