all: serverd-fastcgi serverd update-pulls

DMD=../../source/trunk3/dmd/src/dmd
OUTPUT_DIR=obj

DFLAGS=-m64 -gc

LIBS=-L-lmysqlclient -L-lcurl -L-lcrypto

COMMON_SRC=mysql.d config.d utils.d model/*.d

SERVERD_SRC=serverd.d clientapi/*.d githubapi/*.d loggedin/*.d setup.d validate.d www.d github_apis.d
UPDATE_SRC=update_pulls.d github_apis.d

serverd: $(SERVERD_SRC) $(COMMON_SRC)
	$(DMD) $(DFLAGS) -of$(OUTPUT_DIR)/$@ $^ $(LIBS)

serverd-fastcgi: $(SERVERD_SRC) $(COMMON_SRC)
	$(DMD) -version=FASTCGI $(DFLAGS) -of$(OUTPUT_DIR)/$@ $^ $(LIBS) -L-lfcgi

update-pulls: $(UPDATE_SRC) $(COMMON_SRC)
	$(DMD) $(DFLAGS) -of$(OUTPUT_DIR)/$@ $^ $(LIBS)

clean:
	rm -f $(OUTPUT_DIR)/*.o $(OUTPUT_DIR)/serverd $(OUTPUT_DIR)/serverd-fastcgi $(OUTPUT_DIR)/update-pulls

upload:
	scp $(OUTPUT_DIR)/serverd-fastcgi root@slice-1:/tmp
