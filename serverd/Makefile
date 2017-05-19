
DMD?=dmd
OUTPUT_DIR=obj

DFLAGS=-m64 -gc

LIBS=-L-L/usr/lib64/mysql56 -L-lmysqlclient -L-lcurl -L-lcrypto

ALL_APPS=serverd-fastcgi serverd update-pulls fixup run-hook debug
ALL_APPS_OUTPUT=$(addprefix $(OUTPUT_DIR)/,$(ALL_APPS))
COMMON_SRC=mysql.d config.d utils.d github_apis.d globals.d model/*.d
SERVERD_SRC=serverd.d clientapi/*.d githubapi/*.d loggedin/*.d setup.d validate.d www.d
UPDATE_SRC=update_pulls.d
FIXUP_SRC=fixup.d
RUN_HOOK_SRC=run_hook.d githubapi/hook.d

all: $(ALL_APPS_OUTPUT)

$(OUTPUT_DIR)/serverd: $(SERVERD_SRC) $(COMMON_SRC)
	$(DMD) $(DFLAGS) -of$@ $^ $(LIBS)

$(OUTPUT_DIR)/serverd-fastcgi: $(SERVERD_SRC) $(COMMON_SRC)
	$(DMD) -version=FASTCGI $(DFLAGS) -of$@ $^ $(LIBS) -L-lfcgi

$(OUTPUT_DIR)/update-pulls: $(UPDATE_SRC) $(COMMON_SRC)
	$(DMD) $(DFLAGS) -of$@ $^ $(LIBS)

$(OUTPUT_DIR)/fixup: $(FIXUP_SRC) $(COMMON_SRC)
	$(DMD) $(DFLAGS) -of$@ $^ $(LIBS)

$(OUTPUT_DIR)/run-hook: $(RUN_HOOK_SRC) $(COMMON_SRC)
	$(DMD) $(DFLAGS) -of$@ $^ $(LIBS)

$(OUTPUT_DIR)/debug: debug.d $(COMMON_SRC)
	$(DMD) $(DFLAGS) -of$@ $^ $(LIBS)

clean:
	rm -f $(OUTPUT_DIR)/*.o $(ALL_APPS_OUTPUT)

upload:
	scp $(OUTPUT_DIR)/serverd-fastcgi root@slice-1:/tmp
