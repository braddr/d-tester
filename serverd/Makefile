
DMD?=dmd
OUTPUT_DIR=obj

DFLAGS=-m64 -gc

LIBS=-L-L/usr/lib64/mysql56 -L-lmysqlclient -L-lcurl -L-lcrypto

ALL_APPS=serverd-fastcgi serverd update-pulls fixup test
ALL_APPS_OUTPUT=$(addprefix $(OUTPUT_DIR)/,$(ALL_APPS))
TEST_SRC=test.d mysql_client.d log.d
COMMON_SRC=mysql_client.d config.d log.d utils.d model/*.d
SERVERD_SRC=serverd.d clientapi/*.d githubapi/*.d loggedin/*.d setup.d validate.d www.d github_apis.d
UPDATE_SRC=update_pulls.d github_apis.d
FIXUP_SRC=fixup.d github_apis.d

all: $(ALL_APPS_OUTPUT)

unittest: $(OUTPUT_DIR)/mysql_client_test

$(OUTPUT_DIR):
	mkdir -p $(OUTPUT_DIR)

$(OUTPUT_DIR)/%: | $(OUTPUT_DIR)

$(OUTPUT_DIR)/mysql_client_test: mysql_client.d log.d
	$(DMD) $(DFLAGS) -unittest -main $(DFLAGS) -of$@ $^ $(LIBS)
	$@ || rm $@

$(OUTPUT_DIR)/test: $(TEST_SRC)
	$(DMD) $(DFLAGS) -of$@ $^ $(LIBS)

$(OUTPUT_DIR)/serverd: $(SERVERD_SRC) $(COMMON_SRC)
	$(DMD) $(DFLAGS) -of$@ $^ $(LIBS)

$(OUTPUT_DIR)/serverd-fastcgi: $(SERVERD_SRC) $(COMMON_SRC)
	$(DMD) -version=FASTCGI $(DFLAGS) -of$@ $^ $(LIBS) -L-lfcgi

$(OUTPUT_DIR)/update-pulls: $(UPDATE_SRC) $(COMMON_SRC)
	$(DMD) $(DFLAGS) -of$@ $^ $(LIBS)

$(OUTPUT_DIR)/fixup: $(FIXUP_SRC) $(COMMON_SRC)
	$(DMD) $(DFLAGS) -of$@ $^ $(LIBS)

clean:
	rm -r $(OUTPUT_DIR)

upload:
	scp $(OUTPUT_DIR)/serverd-fastcgi root@slice-1:/tmp
