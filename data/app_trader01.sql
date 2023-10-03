--remove $ signs from google play store db pricing
UPDATE 
	play_store_apps
SET 
	price = REPLACE(
		price, 
		'$',
		'');

/* Query for finding apps in both tables with a tru rating>0.5+avg_rating */

SELECT DISTINCT name,a.price, p.price, primary_genre, genres, ROUND(((a.review_count::numeric*a.rating)+(p.review_count::numeric*p.rating))/(a.review_count::numeric+p.review_count::numeric),1) AS tru_rating
FROM app_store_apps AS a
INNER JOIN play_store_apps AS p
USING(name)
WHERE ((a.review_count::numeric*a.rating)+(p.review_count::numeric*p.rating))/(a.review_count::numeric+p.review_count::numeric) > (1.1*(SELECT AVG(rating)
			   FROM app_store_apps))
	  AND ((a.review_count::numeric*a.rating)+(p.review_count::numeric*p.rating))/(a.review_count::numeric+p.review_count::numeric) > (1.1*(SELECT AVG(rating)
					 FROM play_store_apps))
ORDER BY tru_rating DESC;
					 
/* AVG rating by genre and number of apps in genre */				 

SELECT primary_genre, 
	   genres,
	   AVG(a.rating) AS app_store_rating,
	   AVG(p.rating) AS play_store_rating,
	   AVG(((a.review_count::numeric*a.rating)+(p.review_count::numeric*p.rating))/(a.review_count::int+p.review_count::int)) AS tru_avg, 
	   COUNT(*)
FROM app_store_apps AS a
INNER JOIN play_store_apps AS p
USING(name)
GROUP BY GROUPING SETS ((primary_genre),(genres),())
HAVING COUNT(*) >=10
;

/* All apps that are free on both app stores (50k buying cost) sorted by weighted rating */

SELECT name, 
	   SUM(a.price::money), 
	   SUM(p.price::money), 
	   AVG(((a.review_count::numeric*a.rating)+(p.review_count::numeric*p.rating))/(a.review_count::int+p.review_count::int)) AS tru_avg
FROM app_store_apps AS a
INNER JOIN play_store_apps AS p
USING(name)
WHERE (a.price=0 AND p.price::numeric = 0)
GROUP BY name
ORDER BY tru_avg DESC;

/* Breakdown of Pricing by genre */
WITH ps_av AS	SELECT AVG(price::numeric)::money AS avg_price,
					   CASE WHEN genres IN ('Adventure','Role Playing','Board','Card','Puzzle','Casino','Strategy','Racing','Trivia','Arcade','Simulation','Casual')
								THEN 'Games'
							ELSE genres END AS genre,
					   COUNT(DISTINCT name) AS num_of_apps
				FROM play_store_apps
				GROUP BY genre
				HAVING COUNT(DISTINCT name)>50
				ORDER BY avg_price ASC, 
						 num_of_apps DESC;

 ap_av AS		SELECT AVG(price)::money AS avg_price,
			   		   primary_genre,
			   	COUNT(DISTINCT name) AS num_of_apps
		FROM app_store_apps
		GROUP BY primary_genre
		HAVING COUNT(DISTINCT name)>50
		ORDER BY avg_price ASC, num_of_apps DESC;
		
		
/*Query for finding future earnings from an app purchase based on its rating and pricing*/

WITH cost_purch AS	(SELECT DISTINCT name,
					 		genres,
					 		a.price AS app_price,
					 		p.price AS play_price,
					 		primary_genre,
						    --weighted avg rating based on review_count from each table. Result is multiplied by 4 and rounded to nearest whole number. This is then divided by 4 to effectively round to nearest 0.25
					 		ROUND(((((a.review_count::numeric*a.rating)+(p.review_count::numeric*p.rating))/(a.review_count::numeric+p.review_count::numeric))*4),0)/4 AS tru_rating,
						    --case statement to calculate price of buying
					 		CASE WHEN a.price::numeric < 2.5 AND p.price::numeric < 2.5 THEN 50000
								 WHEN a.price::numeric >= 2.5 AND p.price::numeric < 2.5 THEN 25000+a.price::numeric*10000
					 			 WHEN a.price::numeric < 2.5 AND p.price::numeric >= 2.5 THEN 25000+p.price::numeric*10000
					 			 ELSE (a.price::numeric*10000)+(p.price::numeric*10000)
								 END AS cost_of_purchase
					 FROM app_store_apps AS a
					 INNER JOIN play_store_apps AS p
					 USING(name))


SELECT name,
	   genres,
	   app_price,
	   play_price,
	   primary_genre,
	   tru_rating,
	   --tru_rating is already rounded in the CTE so divide by 0.25 to get amount of 6-mo. periods of longevity then * 0.5 to convert to years. 
	   --*12*4000 because +$5k from in-app purchases-$1k from advertising= +$4k/month then * 12 for each month 
	   (((tru_rating/0.25)*0.5+1)*12*4000)::money AS gross_rev,
	   --same formula as above but subtracting the cost to purchase app from CTE and cast to money
	   ((((tru_rating/0.25)*0.5+1)*12*4000)-cost_of_purchase)::money AS profit_lifetime,
	   cost_of_purchase::money
FROM cost_purch
ORDER BY profit_lifetime DESC
;

/* Query to group prior results by purchase price */

WITH cost_purch AS	(SELECT DISTINCT name,
					 		genres,
					 		a.price AS aprice,
					 		p.price AS pprice,
					 		primary_genre,
						    --weighted avg rating based on review_count from each table. Result is multiplied by 4 and rounded to nearest whole number. This is then divided by 4 to effectively round to nearest 0.25
					 		ROUND(((((a.review_count::numeric*a.rating)+(p.review_count::numeric*p.rating))/(a.review_count::numeric+p.review_count::numeric))*4),0)/4 AS tru_rating,
						    --case statement to calculate price of buying
					 		CASE WHEN a.price::numeric < 2.5 AND p.price::numeric < 2.5 THEN 50000
								 WHEN a.price::numeric >= 2.5 AND p.price::numeric < 2.5 THEN 25000+a.price::numeric*10000
					 			 WHEN a.price::numeric < 2.5 AND p.price::numeric >= 2.5 THEN 25000+p.price::numeric*10000
					 			 ELSE (a.price::numeric*10000)+(p.price::numeric*10000)
								 END AS cost_of_purchase
					 FROM app_store_apps AS a
					 INNER JOIN play_store_apps AS p
					 USING(name)),


	prof_data AS	(SELECT name,
						    genres,
					 		aprice,
					 		pprice,
						    primary_genre,
						    tru_rating,
						    --tru_rating is already rounded in the CTE so divide by 0.25 to get amount of 6-mo. periods of longevity then * 0.5 to convert to years. 
						    --*12*4000 because +$5k from in-app purchases-$1k from advertising= +$4k/month then * 12 for each month 
						    (((tru_rating/0.25)*0.5+1)*12*4000)::money AS gross_rev,
						    --same formula as above but subtracting the cost to purchase app from CTE and cast to money
						    ((((tru_rating/0.25)*0.5+1)*12*4000)-cost_of_purchase)::money AS profit_lifetime,
						    cost_of_purchase::money
					 FROM cost_purch)
					 
SELECT cost_of_purchase,
	   AVG(gross_rev::numeric)::money AS avg_gross,
	   AVG(tru_rating) AS avg_tru_rating,
	   AVG(profit_lifetime::numeric)::money AS avg_profit,
	   COUNT(*) AS num_of_apps
FROM prof_data
GROUP BY cost_of_purchase
ORDER BY cost_of_purchase ASC;


/* Same but with genre */

WITH cost_purch AS	(SELECT DISTINCT name,
					 		genres,
					 		a.price AS aprice,
					 		p.price AS pprice,
					 		primary_genre,
						    --weighted avg rating based on review_count from each table. Result is multiplied by 4 and rounded to nearest whole number. This is then divided by 4 to effectively round to nearest 0.25
					 		ROUND(((((a.review_count::numeric*a.rating)+(p.review_count::numeric*p.rating))/(a.review_count::numeric+p.review_count::numeric))*4),0)/4 AS tru_rating,
						    --case statement to calculate price of buying
					 		CASE WHEN a.price::numeric < 2.5 AND p.price::numeric < 2.5 THEN 50000
								 WHEN a.price::numeric >= 2.5 AND p.price::numeric < 2.5 THEN 25000+a.price::numeric*10000
					 			 WHEN a.price::numeric < 2.5 AND p.price::numeric >= 2.5 THEN 25000+p.price::numeric*10000
					 			 ELSE (a.price::numeric*10000)+(p.price::numeric*10000)
								 END AS cost_of_purchase
					 FROM app_store_apps AS a
					 INNER JOIN play_store_apps AS p
					 USING(name)),


	prof_data AS	(SELECT name,
						    genres,
					 		aprice,
					 		pprice,
						    primary_genre,
						    tru_rating,
						    --tru_rating is already rounded in the CTE so divide by 0.25 to get amount of 6-mo. periods of longevity then * 0.5 to convert to years. 
						    --*12*4000 because +$5k from in-app purchases-$1k from advertising= +$4k/month then * 12 for each month 
						    (((tru_rating/0.25)*0.5+1)*12*4000)::money AS gross_rev,
						    --same formula as above but subtracting the cost to purchase app from CTE and cast to money
						    ((((tru_rating/0.25)*0.5+1)*12*4000)-cost_of_purchase)::money AS profit_lifetime,
						    cost_of_purchase::money
					 FROM cost_purch)
					 
SELECT genres,
	   primary_genre,
	   AVG(tru_rating) AS avg_tru_rating,
	   AVG(profit_lifetime::numeric)::money AS avg_profit,
	   COUNT(*) AS num_of_apps
FROM prof_data
GROUP BY GROUPING SETS ((primary_genre),(genres))
HAVING COUNT(*) >5
;	   

/* Content rating */

WITH cost_purch AS	(SELECT DISTINCT name,
					 		genres,
					 		a.content_rating AS acontent,
					 		p.content_rating AS pcontent,
					 		primary_genre,
						    --weighted avg rating based on review_count from each table. Result is multiplied by 4 and rounded to nearest whole number. This is then divided by 4 to effectively round to nearest 0.25
					 		ROUND(((((a.review_count::numeric*a.rating)+(p.review_count::numeric*p.rating))/(a.review_count::numeric+p.review_count::numeric))*4),0)/4 AS tru_rating,
						    --case statement to calculate price of buying
					 		CASE WHEN a.price::numeric < 2.5 AND p.price::numeric < 2.5 THEN 50000
								 WHEN a.price::numeric >= 2.5 AND p.price::numeric < 2.5 THEN 25000+a.price::numeric*10000
					 			 WHEN a.price::numeric < 2.5 AND p.price::numeric >= 2.5 THEN 25000+p.price::numeric*10000
					 			 ELSE (a.price::numeric*10000)+(p.price::numeric*10000)
								 END AS cost_of_purchase
					 FROM app_store_apps AS a
					 INNER JOIN play_store_apps AS p
					 USING(name)),


	prof_data AS	(SELECT name,
						    genres,
					 		acontent,
					 		pcontent,
						    primary_genre,
						    tru_rating,
						    --tru_rating is already rounded in the CTE so divide by 0.25 to get amount of 6-mo. periods of longevity then * 0.5 to convert to years. 
						    --*12*4000 because +$5k from in-app purchases-$1k from advertising= +$4k/month then * 12 for each month 
						    (((tru_rating/0.25)*0.5+1)*12*4000)::money AS gross_rev,
						    --same formula as above but subtracting the cost to purchase app from CTE and cast to money
						    ((((tru_rating/0.25)*0.5+1)*12*4000)-cost_of_purchase)::money AS profit_lifetime,
						    cost_of_purchase::money
					 FROM cost_purch)
					 
SELECT 
	   prof_data.pcontent,
	   prof_data.acontent,
	   AVG(gross_rev::numeric)::money AS avg_gross,
	   AVG(cost_of_purchase::numeric)::money AS avg_cost,
	   AVG(tru_rating) AS avg_tru_rating,
	   AVG(profit_lifetime::numeric)::money AS avg_profit,
	   COUNT(DISTINCT name) AS num_of_apps
FROM prof_data
GROUP BY GROUPING SETS ((prof_data.pcontent),(prof_data.acontent),())
HAVING COUNT(*) >5
;	



