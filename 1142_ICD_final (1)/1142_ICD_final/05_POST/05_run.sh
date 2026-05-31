cycle=$(grep -oE "[0-9]+\.[0-9]+" cycle.txt)
vcs -f post.f -full64 -R -debug_access+all +v2k +maxdelays -negdelay +neg_tchk +define+SDF_POST+tb1 +define+CYCLE=${cycle} | tee run.log