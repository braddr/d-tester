all: serverd-fastcgi serverd update-pulls

DMD=../../source/trunk3/dmd/src/dmd

DFLAGS=-m64 -gc

LIBS=-L-lmysqlclient -L-lcurl

COMMON_SRC=mysql.d config.d utils.d

SERVERD_SRC=serverd.d p_*.d setup.d www.d
UPDATE_SRC=update_pulls.d

serverd: $(SERVERD_SRC) $(COMMON_SRC)
	$(DMD) $(DFLAGS) -of$@ $^ $(LIBS)

serverd-fastcgi: $(SERVERD_SRC) $(COMMON_SRC)
	$(DMD) -version=FASTCGI $(DFLAGS) -of$@ $^ $(LIBS) -L-lfcgi

update-pulls: $(UPDATE_SRC) $(COMMON_SRC)
	$(DMD) $(DFLAGS) -of$@ $^ $(LIBS)

clean:
	rm -f *.o serverd serverd-fastcgi update-pulls

