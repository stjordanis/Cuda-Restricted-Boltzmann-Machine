
NVCC      = nvcc
CXXFLAGS  = 
INC       =
LIBS      = -lcublas -lcurand -lm
OPTIMIZE  = -O2
NVCCFLAGS = -ccbin="/usr/bin/g++" -Xcompiler="$(CXXFLAGS)" -std=c++11 -arch=sm_30 $(INC) $(LIBS) $(OPTIMIZE)
BUILD_DIR = bin
TEST_DIR  = tests

MAIN     = main.cpp
EXEC     = final
SOURCES  = $(wildcard *.cpp)
SOURCES += $(wildcard *.cu)
HEADERS  = $(wildcard *.h)
OBJECTS  = $(patsubst %.cpp,%.o,$(patsubst %.cu,%.o,$(SOURCES)))
BUILDS   = $(OBJECTS:%.o=$(BUILD_DIR)/%.o)

export # export all variables for sub-make

# Main target
all: dirs $(BUILDS)
	$(NVCC) $(NVCCFLAGS) $(BUILDS) -o $(EXEC)

# To obtain object files
$(BUILD_DIR)/%.o: %.cpp $(HEADERS)
	$(NVCC) -c $(NVCCFLAGS) $< -o $@

$(BUILD_DIR)/%.o: %.cu $(HEADERS)
	$(NVCC) -c $(NVCCFLAGS) $< -o $@

.PHONY: dirs clean tests

dirs:
	@[ -d $(BUILD_DIR) ] ||  (echo "Creating directories" && mkdir -p $(BUILD_DIR))

clean:
	rm -rf $(EXEC) $(BUILD_DIR)

tests:
	$(MAKE) -C $(TEST_DIR) bin/$(TARGET) 
