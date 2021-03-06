findTarget <- function(args) {
	dist <- vapply(args, is.distObjRef, logical(1))
	if (!any(dist)) return(root())
	sizes <- lapply(args[dist], function(x) sum(size(x)))
	args[dist][[which.max(sizes)]] # largest 
}

is.AsIs <- function(x) inherits(x, "AsIs")
unAsIs <- function(x) {
	class(x) <- class(x)[!class(x) == "AsIs"]
	x
}

# emerge dispatches on arg

emerge.default <- function(arg, target) arg

emerge.AsIs <- function(arg, target) unAsIs(arg)

emerge.chunkRef <- function(arg, target) {
	tryCatch(get(as.character(desc(arg)), envir = .largeScaleRChunks),
		 error = function(e) osrvGet(arg))
}

emerge.distObjRef <- function(arg, target) {
	if (missing(target) || is.null(target)) {
		chunks <- sapply(chunkRef(arg), emerge, 
				 simplify=FALSE, USE.NAMES=FALSE)
		names(chunks) <- NULL
		return(do.call(combine, chunks))
	}

	toAlign <- alignment(arg, target) 
	Stub <- sapply(toAlign$Stub, emerge,
		       simplify=FALSE, USE.NAMES=FALSE)
	names(Stub) <- NULL

	if (length(Stub) == 1) {
		index(Stub[[1]], seq(toAlign$HEAD$FROM, toAlign$HEAD$TO))
	} else do.call(combine, 
		       c(list(index(Stub[[1]], seq(toAlign$HEAD$FROM, 
						  toAlign$HEAD$TO))), 
			 Stub[-c(1, length(Stub))], 
			 list(index(Stub[[length(Stub)]], seq(toAlign$TAIL$FROM,
							    toAlign$TAIL$TO)))))
}

# distribute dispatches on target

distribute.distObjRef <- function(arg, target) {
	if (is.distObjRef(arg) ||
	    is.chunkRef(arg)   ||
	    is.AsIs(arg))
		return(arg)
	splits <- split(arg, cumsum(seq(size(arg)) %in% from(target)))
	chunks <- mapply(distribute,
			 splits, chunkRef(target)[seq(length(splits))],
			 SIMPLIFY = FALSE, USE.NAMES=FALSE)
	names(chunks) <- NULL
	x <- distObjRef(chunks)
	x
}

distribute.chunkRef <- function(arg, target) {
	do.ccall("identity", list(arg), target = target)
}

# scatter into <target>-many pieces over the general cluster
distribute.integer <- function(arg, target) {
	stopifnot(target > 0)
	chunks <- if (target == 1) {
		list(arg) 
		} else split(arg, cut(seq(size(arg)), breaks=target))
	names(chunks) <- NULL
	chunkRefs <- sapply(chunks, function(chunk)
			     do.ccall("identity", list(chunk),
					       root()),
			     simplify = FALSE, USE.NAMES = FALSE)
	names(chunkRefs) <- NULL
	distObjRef(chunkRefs)
}
distribute.numeric <- distribute.integer

# `alignment` returns list of form:
#  .
#  ├── HEAD
#  │   ├── FROM
#  │   └── TO
#  ├── Stub
#  └── TAIL
#      ├── FROM
#      └── TO
alignment <- function(arg, target) {
	stopifnot(is.distObjRef(arg),
		  is.chunkRef(target))

	toAlign 	<- list()
	argChunks	<- chunkRef(arg)
	argFrom 	<- from(arg)
	argTo 		<- to(arg)
	argSize 	<- sum(size(arg))
	targetFrom 	<- from(target)
	targetTo 	<- to(target)
	targetSize 	<- size(target)

	# (x-1%%y)-1 to force a 1->n cycle instead of 0->n-1 for R's 1-indexing
	headFromAbs <- ((targetFrom-1L) %% argSize)+1L
	headStubNum <- which(headFromAbs <= argTo)[1]
	headFromRel <- headFromAbs - argFrom[headStubNum] + 1L

	tailToAbs <- if (targetSize > argSize)  #clip rep, force local recycling
		((headFromAbs-2L)%%argSize)+1L else ((targetTo-1L)%%argSize)+1L
	tailStubNum <- which(tailToAbs <= argTo)[1]
	tailToRel <- tailToAbs - argFrom[tailStubNum] + 1L

	Stub <- if ((targetSize >= argSize && headFromAbs > argFrom[1]) ||
		   (targetSize < argSize && headFromAbs > tailToAbs)) # modular
		c(seq(headStubNum, length(argChunks)), seq(1L, tailStubNum)) else
			seq(headStubNum, tailStubNum)

	toAlign <- list()
	toAlign$HEAD$FROM <- headFromRel
	toAlign$HEAD$TO <- if (length(Stub) == 1) 
		tailToRel else argTo[headStubNum] - argFrom[headStubNum] + 1L
	toAlign$Stub <- argChunks[Stub]
	toAlign$TAIL$FROM <- 1L
	toAlign$TAIL$TO <- tailToRel

	toAlign
}

index <- function(x, i) {
       ndim <- if (is.null(dim(x))) 1L else length(dim(x))
       l <- as.list(quote(x[]))[3]
       eval(as.call(
                    c(list(quote(`[`)),
                      list(quote(x)),
                      list(quote(i)),
                      rep(l, ndim-1L))
                    ))
}

osrvCmd <- function(s, cmd) {
       writeBin(charToRaw(cmd), s)
       while (!length(a <- readBin(s, raw(), 32))) {}
       i <- which(a == as.raw(10))
       if (!length(i)) stop("Invalid answer")
       res <- gsub("[\r\n]+","",rawToChar(a[1:i[1]]))
       sr <- strsplit(res, " ", TRUE)[[1]]
       ## object found
       if (sr[1] == "OK" && length(sr) > 1) {
               len <- as.numeric(sr[2])
               p <- if (i[1] < length(a)) a[-(1:i[1])] else raw()
               ## read the rest of the object
               while (length(p) < len)
                       p <- c(p, readBin(s, raw(), len - length(p)))
               p
       } else if (sr[1] == "OK") {
               TRUE
       } else stop("Answer: ", sr[1])
}


osrvGet <- function(x) {
	stateLog(paste("RCV", desc(getUserProcess()),
		       desc(x))) # RCV X Y - Receiving at worker X, chunk Y
       s <- socketConnection(host(x), port=port(x), open="a+b")
       sv <- osrvCmd(s, paste0("GET", " ", desc(x), "\n"))
       close(s)
       v <- unserialize(sv)
       v
}
