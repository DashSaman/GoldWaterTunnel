import sys, zipfile

# Structurally valid ZIP and plausible executable, but never an official asset.
with zipfile.ZipFile(sys.argv[1], 'w') as archive:
    archive.writestr('Waterwall', '#!/usr/bin/env bash\n'
                     'touch "$GWT_TEST_MARKER"\n'
                     'echo "Waterwall version 1.46.96"\n')
