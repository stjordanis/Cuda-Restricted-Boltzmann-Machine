# Directories
BUILD_DIR = bin
TEST_DIR  = tests
INC_DIR   = include

# Flags
NVCC      = nvcc
CXXFLAGS  =
DEBUG     = -g -DDEBUG
ARCH      = -arch=compute_30 -code=sm_30 
INC       = -I$(INC_DIR)
LIBS      = -lcublas -lcurand -lm #-lcublas_device -lcudadevrt 
OPTIMIZE  = #-O2
NVCCFLAGS = -ccbin="$(shell which c++)" -Xcompiler="$(CXXFLAGS)" -std=c++11 $(ARCH) $(INC) $(OPTIMIZE) $(DEBUG)

# Target
MAIN     = main.cpp
EXEC     = final
SOURCES  = $(wildcard *.cpp)
SOURCES += $(wildcard *.cu)
HEADERS += $(wildcard $(LIB)/*.h)
OBJECTS  = $(patsubst %.cpp,%.o,$(patsubst %.cu,%.o,$(SOURCES)))
BUILDS   = $(OBJECTS:%.o=$(BUILD_DIR)/%.o)

export # export all variables for sub-make

# Main target
all: dirs $(BUILDS)
	$(NVCC) $(LIBS) $(BUILDS) -o $(EXEC)

# To obtain object files
$(BUILD_DIR)/%.o: %.cpp $(HEADERS)
	$(NVCC) -c $(NVCCFLAGS) $< -o $@

$(BUILD_DIR)/%.o: %.cu $(HEADERS)
	$(NVCC) -c $(NVCCFLAGS) $< -o $@

.PHONY: dirs clean tests run

dirs:
	@[ -d $(BUILD_DIR) ] ||  (echo "Creating directories: $(BUILD_DIR)" && mkdir -p $(BUILD_DIR))

clean:
	rm -rf $(EXEC) $(BUILD_DIR)

tests:
	$(MAKE) -C $(TEST_DIR) bin/$(TARGET) 

run:
	# [Output directory] [Training data] [Learning rate] [Epoch number] [Train data size]
	./$(EXEC) out data/train-images-idx3-ubyte 0.1 1 4
