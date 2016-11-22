# download and extract Solr + samples
wget http://mirrors.hostingromania.ro/apache.org/lucene/solr/6.3.0/solr-6.3.0.tgz
tar zxf solr-6.3.0.tgz
cd solr-6.3.0

# start SolrCloud
bin/solr start -c
# Solr Admin is sooo nice, look at all the heap stats and everything! Did you set the heap size, BTW?

# create schemaless collection with 2 shards
bin/solr create_collection -c videos1 -shards 2 -replicationFactor 1
# admire Solr Admin some more: graph, tree

# index data
git clone https://github.com/sematext/berlin-buzzwords-samples.git
cd berlin-buzzwords-samples/2014/sample-documents/
ls
for file in *.json; do echo $file; curl localhost:8983/solr/videos1/update -H 'Content-type:application/json' -d "[`cat $file`]"; echo; done

# where are my docs
http://localhost:8983/solr/videos1/select?q=*:*
# commit
http://localhost:8983/solr/videos1/update?commit=true
# this time in JSON
http://localhost:8983/solr/videos1/select?q=*:*&wt=json&indent=true
# pagination
http://localhost:8983/solr/videos1/select?q=*:*&start=2&rows=2

# search for Solr
http://localhost:8983/solr/videos1/select?q=title:solr
# check the schema of the title field
# how about _text_
http://localhost:8983/solr/videos1/select?q=_text_:solr

# sort by upload date
http://localhost:8983/solr/videos1/select?q=_text_:solr&sort=upload_date desc

# adjust schema
curl -XPOST -H 'Content-type:application/json' --data-binary '{
  "replace-field":{
     "name":"upload_date",
     "type":"tdate" },
  "replace-field":{
     "name":"title",
     "type":"text_en" },
  "replace-field":{
     "name":"uploaded_by",
     "type":"string" },
  "replace-field":{
     "name":"likes",
     "type":"tlong" },
  "replace-field":{
     "name":"views",
     "type":"long" },
  "replace-field":{
     "name":"url",
     "type":"string",
     "indexed": false }
}' http://localhost:8983/solr/videos1/schema

# while we're at it, switch autocommit on
curl localhost:8983/solr/videos1/config -H 'Content-type:application/json' -d '{
  "set-property": {
    "updateHandler.autoSoftCommit.maxTime":5000
  }
}'

# reindex
localhost:8983/solr/admin/collections?action=DELETE&name=videos1

localhost:8983/solr/admin/collections?action=CREATE&name=videos1&numShards=2&replicationFactor=1&maxShardsPerNode=2&collection.configName=videos1

for file in *.json; do echo $file; curl localhost:8983/solr/videos1/update -H 'Content-type:application/json' -d "[`cat $file`]"; echo; done

# search for Solr, take two
http://localhost:8983/solr/videos1/select?q=title:solr
# with stemming, too
http://localhost:8983/solr/videos1/select?q=title:search
# sort
http://localhost:8983/solr/videos1/select?q=title:solr&sort=upload_date desc


# relevancy

# Solr OR Logs
http://localhost:8983/solr/videos1/select?q=title:solr OR title:logs&fl=title,tags,likes,score

# and the tags field, too
http://localhost:8983/solr/videos1/select?defType=dismax&q=solr logs&qf=title+tags&fl=title,tags,likes,score

# boost tags more:
http://localhost:8983/solr/videos1/select?defType=dismax&q=solr logs&qf=title+tags^3&fl=title,tags,likes,score

# boost by likes, too (though the square root only)
http://localhost:8983/solr/videos1/select?defType=dismax&q=solr logs&qf=title+tags^3&fl=title,tags,likes,score&bf=sqrt(field(likes))


# facets

# popular tags in 2015
http://localhost:8983/solr/videos1/select?q=upload_date:[2014-01-01T00:00:00Z TO 2015-01-01T00:00:00Z]&rows=1&facet=true&facet.field=tags&facet.mincount=1

# posts per year. JSON style
curl localhost:8983/solr/videos1/query -d '{
  query : "*:*",
  facet : {
    years : {
      range : {
        field : "upload_date",
        start : "2012-01-01T00:00:00Z",
        end : "2016-01-01T00:00:00Z",
        gap : "+1YEARS"
      }
    }
 }
}'

# top 2 tags per year
curl localhost:8983/solr/videos1/query -d '{
  query : "*:*",
  facet : {
    years : {
      range : {
        field : "upload_date",
        start : "2012-01-01T00:00:00Z",
        end : "2016-01-01T00:00:00Z",
        gap : "+1YEARS",
        facet : {
          top_tags : {
            terms : {
              field: tags,
              limit: 2
            }
          }
        }
      }
    }
 }
}'

# rollup a high cardinality field (e.g. uploaded_by) and sum up views per uploader
curl --data-urlencode 'expr=rollup(
   search(videos1, q=*:*, fl="uploaded_by,views", qt="/export", sort="uploaded_by asc"),
   over="uploaded_by",
   sum(views)
)' http://localhost:8983/solr/videos1/stream
